#!/bin/bash
set -e

# Market Making Game - Test Runner
# Runs all tests across the codebase

echo "🧪 Running All Tests"
echo "===================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

FAILED=0

# C++ Engine Tests
echo -e "${BLUE}Testing C++ Engine...${NC}"
cd engine/build 2>/dev/null || (echo "❌ Engine not built. Run build_all.sh first" && exit 1)

if ctest --output-on-failure; then
    echo -e "${GREEN}✓ C++ tests passed${NC}"
else
    echo -e "${RED}✗ C++ tests failed${NC}"
    FAILED=1
fi

cd ../..

# Python Gateway Tests
echo -e "${BLUE}Testing Python Gateway...${NC}"
cd gateway

if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
fi

if [ -d "tests" ] && [ "$(ls -A tests/*.py 2>/dev/null)" ]; then
    if python -m pytest tests/ -v; then
        echo -e "${GREEN}✓ Python tests passed${NC}"
    else
        echo -e "${RED}✗ Python tests failed${NC}"
        FAILED=1
    fi
else
    echo "⚠️  No Python tests found"
fi

cd ..

# Flutter Tests
echo -e "${BLUE}Testing Flutter App...${NC}"
cd frontend

if command -v flutter &> /dev/null; then
    if flutter test; then
        echo -e "${GREEN}✓ Flutter tests passed${NC}"
    else
        echo -e "${RED}✗ Flutter tests failed${NC}"
        FAILED=1
    fi
else
    echo "⚠️  Flutter not installed, skipping"
fi

cd ..

# Summary
echo ""
echo "===================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi

