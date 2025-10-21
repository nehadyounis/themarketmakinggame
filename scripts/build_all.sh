#!/bin/bash
set -e

# Market Making Game - Production Build Script
# Builds all components for deployment

echo "🏗️  Building Market Making Game (Production)"
echo "=============================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

BUILD_DIR="build"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Clean previous builds
echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/{engine,gateway,frontend}

# Step 1: Build C++ Engine
echo -e "${BLUE}📦 Building C++ engine...${NC}"
cd engine
mkdir -p build
cd build

cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_PYTHON_BINDINGS=ON -DBUILD_TESTS=ON ..
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Run tests
echo "Running engine tests..."
ctest --output-on-failure

# Copy artifacts
cp libmmg_engine.* ../../$BUILD_DIR/engine/ 2>/dev/null || true
cp mmg_engine*.so ../../$BUILD_DIR/engine/ 2>/dev/null || true
cp mmg_engine*.dylib ../../$BUILD_DIR/engine/ 2>/dev/null || true

cd ../..
echo -e "${GREEN}✓ Engine built and tested${NC}"

# Step 2: Package Gateway
echo -e "${BLUE}🐍 Packaging Python gateway...${NC}"
cd gateway

# Create requirements with pinned versions
pip freeze > $BUILD_DIR/gateway/requirements.txt 2>/dev/null || cp requirements.txt ../$BUILD_DIR/gateway/

# Copy source files
cp -r app ../$BUILD_DIR/gateway/
cp requirements.txt ../$BUILD_DIR/gateway/ 2>/dev/null || true

# Copy engine binary
cp ../engine/build/mmg_engine*.so ../$BUILD_DIR/gateway/ 2>/dev/null || true
cp ../engine/build/mmg_engine*.dylib ../$BUILD_DIR/gateway/ 2>/dev/null || true

cd ..
echo -e "${GREEN}✓ Gateway packaged${NC}"

# Step 3: Build Flutter Web
echo -e "${BLUE}📱 Building Flutter web app...${NC}"
cd frontend

if ! command -v flutter &> /dev/null; then
    echo "❌ Error: Flutter not found in PATH"
    exit 1
fi

flutter pub get
flutter build web --release --base-href /

# Copy build output
cp -r build/web/* ../$BUILD_DIR/frontend/

cd ..
echo -e "${GREEN}✓ Flutter web built${NC}"

# Step 4: Create deployment package
echo -e "${BLUE}📦 Creating deployment package...${NC}"
cd $BUILD_DIR

# Create tarball
TARBALL="mmg_${TIMESTAMP}.tar.gz"
tar -czf $TARBALL engine gateway frontend

echo -e "${GREEN}✓ Created deployment package: $BUILD_DIR/$TARBALL${NC}"

cd ..

# Step 5: Build Docker images (optional)
if command -v docker &> /dev/null; then
    echo -e "${BLUE}🐳 Building Docker images...${NC}"
    
    # Build gateway image
    docker build -t mmg-gateway:latest -f docker/Dockerfile.gateway .
    
    # Build nginx image
    docker build -t mmg-nginx:latest -f docker/Dockerfile.nginx .
    
    echo -e "${GREEN}✓ Docker images built${NC}"
else
    echo "⚠️  Docker not found, skipping image build"
fi

# Summary
echo ""
echo "=============================================="
echo -e "${GREEN}✅ Build Complete!${NC}"
echo "=============================================="
echo "Build directory: $BUILD_DIR"
echo "Deployment package: $BUILD_DIR/$TARBALL"
echo ""
echo "To deploy:"
echo "  1. Extract tarball on server"
echo "  2. Run with Docker Compose (see README)"
echo "  3. Or use provided deployment scripts"
echo "=============================================="

