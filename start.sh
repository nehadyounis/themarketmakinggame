#!/bin/bash
set -e

# Market Making Game - Complete Startup Script
# This script handles everything: cleanup, build checks, and startup

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Market Making Game - Starting All Services${NC}"
echo "=================================================="
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Shutting down services...${NC}"
    kill $(jobs -p) 2>/dev/null || true
    exit
}

trap cleanup SIGINT SIGTERM

# Step 1: Free ports
echo -e "${BLUE}🔌 Freeing ports 8000 and 3000...${NC}"
lsof -ti:8000 | xargs kill -9 2>/dev/null && echo "  ✓ Port 8000 freed" || echo "  ✓ Port 8000 already free"
lsof -ti:3000 | xargs kill -9 2>/dev/null && echo "  ✓ Port 3000 freed" || echo "  ✓ Port 3000 already free"
sleep 2

# Step 2: Check C++ engine
echo -e "\n${BLUE}🔨 Checking C++ Engine...${NC}"
if [ ! -f "engine/build/mmg_engine.cpython-313-darwin.so" ]; then
    echo "  Building engine..."
    cd engine/build
    make -j$(sysctl -n hw.ncpu) > /dev/null 2>&1
    cd ../..
    echo -e "  ${GREEN}✓ Engine built${NC}"
else
    echo -e "  ${GREEN}✓ Engine already built${NC}"
fi

# Step 3: Copy engine to gateway
echo -e "\n${BLUE}📦 Copying engine binary...${NC}"
cp engine/build/mmg_engine*.so gateway/ 2>/dev/null || cp engine/build/mmg_engine*.dylib gateway/ 2>/dev/null
echo -e "  ${GREEN}✓ Engine binary ready${NC}"

# Step 4: Check Python environment
echo -e "\n${BLUE}🐍 Checking Python environment...${NC}"
cd gateway
if [ ! -d "venv" ]; then
    echo "  Creating virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -q --upgrade pip
    pip install -q -r requirements.txt
    echo -e "  ${GREEN}✓ Python environment created${NC}"
else
    echo -e "  ${GREEN}✓ Virtual environment exists${NC}"
fi
cd ..

# Step 5: Start Gateway
echo -e "\n${BLUE}🌐 Starting Gateway...${NC}"
cd gateway
source venv/bin/activate
nohup python -m app.main > gateway.log 2>&1 &
GATEWAY_PID=$!
echo $GATEWAY_PID > gateway.pid
cd ..

# Wait for gateway to be ready
echo "  Waiting for gateway to initialize..."
for i in {1..10}; do
    if curl -s http://localhost:8000/ > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Gateway running (PID: $GATEWAY_PID)${NC}"
        break
    fi
    sleep 1
done

# Step 6: Start Flutter
echo -e "\n${BLUE}📱 Starting Flutter Web...${NC}"
cd frontend

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Error: Flutter not found in PATH${NC}"
    echo "Please install Flutter: https://flutter.dev/docs/get-started/install"
    kill $GATEWAY_PID
    exit 1
fi

# Get dependencies if needed
if [ ! -d ".dart_tool" ]; then
    echo "  Getting Flutter dependencies..."
    flutter pub get > /dev/null 2>&1
fi

# Start Flutter
nohup flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0 > flutter.log 2>&1 &
FLUTTER_PID=$!
echo $FLUTTER_PID > flutter.pid
cd ..

# Wait for Flutter to be ready
echo "  Waiting for Flutter to build (this takes ~25 seconds)..."
sleep 25

# Check if Flutter is serving
if curl -s http://localhost:3000/ > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Flutter running (PID: $FLUTTER_PID)${NC}"
else
    echo -e "  ${YELLOW}⚠️  Flutter may still be building, check logs${NC}"
fi

# Display status
echo ""
echo "=================================================="
echo -e "${GREEN}✅ All Services Started Successfully!${NC}"
echo "=================================================="
echo ""
echo "🌐 Access Points:"
echo "   Frontend:  http://localhost:3000"
echo "   Gateway:   http://localhost:8000"
echo "   API Docs:  http://localhost:8000/docs"
echo ""
echo "📝 Logs:"
echo "   Gateway:   tail -f gateway/gateway.log"
echo "   Flutter:   tail -f frontend/flutter.log"
echo ""
echo "🔧 Process IDs:"
echo "   Gateway:   $GATEWAY_PID (saved in gateway/gateway.pid)"
echo "   Flutter:   $FLUTTER_PID (saved in frontend/flutter.pid)"
echo ""
echo "💡 How to Use:"
echo "   1. Open http://localhost:3000 in your browser"
echo "   2. Enter your name"
echo "   3. Click 'Create & Host Game' to become Exchange"
echo "   4. OR enter a room code and click 'Join Game as Trader'"
echo ""
echo "🛑 To stop all services:"
echo "   Press Ctrl+C or run: ./stop.sh"
echo ""
echo "=================================================="
echo "Services running in background. Press Ctrl+C to stop all."

# Keep script running
wait

