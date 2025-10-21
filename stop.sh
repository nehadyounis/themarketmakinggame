#!/bin/bash

# Market Making Game - Stop Script
# Stops all running services

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🛑 Stopping Market Making Game Services${NC}"
echo "==========================================="

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Stop Gateway
if [ -f "gateway/gateway.pid" ]; then
    GATEWAY_PID=$(cat gateway/gateway.pid)
    if kill -0 $GATEWAY_PID 2>/dev/null; then
        kill $GATEWAY_PID 2>/dev/null
        echo -e "  ${GREEN}✓ Stopped Gateway (PID: $GATEWAY_PID)${NC}"
    else
        echo "  Gateway already stopped"
    fi
    rm -f gateway/gateway.pid
fi

# Stop Flutter
if [ -f "frontend/flutter.pid" ]; then
    FLUTTER_PID=$(cat frontend/flutter.pid)
    if kill -0 $FLUTTER_PID 2>/dev/null; then
        kill $FLUTTER_PID 2>/dev/null
        echo -e "  ${GREEN}✓ Stopped Flutter (PID: $FLUTTER_PID)${NC}"
    else
        echo "  Flutter already stopped"
    fi
    rm -f frontend/flutter.pid
fi

# Kill any remaining processes on the ports
echo ""
echo "Cleaning up ports..."
lsof -ti:8000 | xargs kill -9 2>/dev/null && echo "  ✓ Port 8000 freed" || echo "  ✓ Port 8000 already free"
lsof -ti:3000 | xargs kill -9 2>/dev/null && echo "  ✓ Port 3000 freed" || echo "  ✓ Port 3000 already free"

echo ""
echo -e "${GREEN}✅ All services stopped${NC}"
echo "==========================================="

