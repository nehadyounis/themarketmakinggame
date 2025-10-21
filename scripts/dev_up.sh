#!/bin/bash
set -e

# Market Making Game - Development Startup Script
# This script starts all services for local development

echo "🚀 Starting Market Making Game (Development Mode)"
echo "=================================================="

# Check if running from project root
if [ ! -d "engine" ] || [ ! -d "gateway" ] || [ ! -d "frontend" ]; then
    echo "❌ Error: Must run from project root"
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Build C++ engine
echo -e "${BLUE}📦 Building C++ engine...${NC}"
cd engine
mkdir -p build
cd build

if [ ! -f "Makefile" ]; then
    echo "Running CMake..."
    cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_PYTHON_BINDINGS=ON ..
fi

make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo -e "${GREEN}✓ Engine built successfully${NC}"

# Copy Python module to gateway
if [ -f "mmg_engine*.so" ] || [ -f "mmg_engine*.dylib" ] || [ -f "mmg_engine*.pyd" ]; then
    echo "Copying Python bindings to gateway..."
    cp mmg_engine* ../../gateway/ 2>/dev/null || true
fi

cd ../..

# Step 2: Setup Python virtual environment
echo -e "${BLUE}🐍 Setting up Python environment...${NC}"
cd gateway

if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt
echo -e "${GREEN}✓ Python environment ready${NC}"

cd ..

# Step 3: Install Flutter dependencies
echo -e "${BLUE}📱 Setting up Flutter...${NC}"
cd frontend

if ! command -v flutter &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Flutter not found in PATH${NC}"
    echo "Please install Flutter: https://flutter.dev/docs/get-started/install"
else
    flutter pub get
    echo -e "${GREEN}✓ Flutter dependencies installed${NC}"
fi

cd ..

# Step 4: Create exports directory
mkdir -p exports

# Step 5: Start services
echo -e "${BLUE}🌐 Starting services...${NC}"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Shutting down services...${NC}"
    kill $(jobs -p) 2>/dev/null || true
    exit
}

trap cleanup SIGINT SIGTERM

# Start Gateway
echo "Starting Gateway on http://localhost:8000"
cd gateway
source venv/bin/activate
python -m app.main &
GATEWAY_PID=$!
cd ..

# Wait for gateway to start
sleep 2

# Start Flutter Web
if command -v flutter &> /dev/null; then
    echo "Starting Flutter Web on http://localhost:3000"
    cd frontend
    flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0 &
    FLUTTER_PID=$!
    cd ..
else
    echo -e "${YELLOW}⚠️  Skipping Flutter (not installed)${NC}"
fi

echo -e "\n${GREEN}✅ All services started!${NC}"
echo "=================================================="
echo "Gateway:  http://localhost:8000"
echo "Frontend: http://localhost:3000"
echo "API Docs: http://localhost:8000/docs"
echo "Stats:    http://localhost:8000/stats"
echo ""
echo "Press Ctrl+C to stop all services"
echo "=================================================="

# Wait for background processes
wait

