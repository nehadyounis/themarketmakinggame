# 🚀 Quick Start Guide

Get the Market Making Game up and running in 5 minutes!

## Prerequisites

Ensure you have:
- **C++ compiler**: GCC 9+ or Clang 10+
- **CMake**: 3.15 or higher
- **Python**: 3.11 or higher
- **Flutter**: 3.16+ (for frontend)

## Option 1: One-Command Start (Recommended)

```bash
./scripts/dev_up.sh
```

This will:
1. Build the C++ engine
2. Set up Python environment
3. Install dependencies
4. Start all services

Access at:
- **Frontend**: http://localhost:3000
- **API**: http://localhost:8000

## Option 2: Docker Deployment

```bash
# Build everything
./scripts/build_all.sh

# Start with Docker Compose
docker-compose up -d

# Access at http://localhost
```

## Option 3: Manual Setup

### Step 1: Build Engine
```bash
cd engine
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_PYTHON_BINDINGS=ON ..
make -j4
cd ../..
```

### Step 2: Setup Gateway
```bash
cd gateway
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp ../engine/build/mmg_engine*.so .
python -m app.main &
cd ..
```

### Step 3: Run Frontend
```bash
cd frontend
flutter pub get
flutter run -d web-server --web-port 3000
```

## 🎮 First Session

### As Exchange Host:
1. Open http://localhost:3000
2. Enter your name and select "Exchange" role
3. Click "Create Room" → Note the room code
4. Add instruments (e.g., "BTC" as SCALAR)
5. Wait for traders to join
6. Settle instruments when done

### As Trader:
1. Open http://localhost:3000
2. Enter your name and select "Trader" role
3. Enter room code and click "Join Room"
4. Select an instrument from the list
5. Click on price ladder to place orders
6. Monitor your P&L in real-time

## 🧪 Run Tests

```bash
./scripts/test_all.sh
```

Or individually:
```bash
# C++ Engine
cd engine/build && ctest

# Python Gateway
cd gateway && pytest tests/

# Flutter
cd frontend && flutter test

# E2E Acceptance Tests
cd gateway && python tests/test_e2e.py
```

## 📊 Example Session

```bash
# Terminal 1: Start services
./scripts/dev_up.sh

# Terminal 2: Run acceptance test
cd gateway
source venv/bin/activate
python tests/test_e2e.py
```

Expected output:
```
✓ Room created: ABC123
✓ Traders joined: Alice (ID 1), Bob (ID 2)
✓ Instrument added: TEST (ID 1)
✓ Orders placed and matched
✓ Final P&L: Alice: $50.00, Bob: -$50.00
✓ Zero-sum verified
✅ Test passed!
```

## 🐛 Troubleshooting

### "Engine not found"
```bash
cd engine/build
make
cp mmg_engine*.so ../../gateway/
```

### "Flutter not found"
```bash
# Install Flutter: https://flutter.dev/docs/get-started/install
flutter doctor
flutter config --enable-web
```

### "Port 8000 already in use"
```bash
# Kill existing process
lsof -ti:8000 | xargs kill -9
```

### "WebSocket connection failed"
- Check gateway is running: `curl http://localhost:8000/`
- Check firewall settings
- Verify WebSocket URL in `frontend/lib/screens/lobby_screen.dart`

## 📚 Next Steps

- Read the [README.md](README.md) for detailed documentation
- Check [CONTRIBUTING.md](CONTRIBUTING.md) to contribute
- Review [Architecture Overview](docs/architecture.md)
- Join our community discussions

## 💡 Tips

1. **Development**: Use `./scripts/dev_up.sh` for hot-reload
2. **Production**: Use Docker Compose for deployment
3. **Testing**: Run tests before committing changes
4. **Performance**: Monitor with `http://localhost:8000/stats`

## 🆘 Need Help?

- **Issues**: Open a GitHub issue
- **Questions**: Start a discussion
- **Chat**: Join our Discord community

Happy trading! 🎯📈

