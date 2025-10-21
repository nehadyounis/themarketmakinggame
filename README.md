# Market Making Game 🎮📈

A real-time multiplayer trading simulation game where one Exchange host creates markets and 3-20 Traders compete to maximize their P&L. Features a high-performance C++ matching engine, Python WebSocket gateway, and Flutter web frontend.

## 🎯 Features

- **Real-time multiplayer**: 1 Exchange + 3-20 Traders in the same room
- **Market types**: SCALAR (underlying) and OPTIONS (Call/Put)
- **Professional UI**: Click-trading ladder + options chain
- **Live P&L tracking**: Realized and unrealized P&L with position management
- **In-memory trading**: Zero latency, writes CSV/SQLite on session close
- **Cost-efficient**: Runs on a single small VM (1 vCPU/2GB)

## 🏗️ Architecture

```
┌─────────────────┐
│  Flutter Web    │  ← Browser UI (Lobby, Terminal, Console)
│   (Nginx)       │
└────────┬────────┘
         │ WebSocket JSON
┌────────▼────────┐
│  FastAPI/WS     │  ← Python Gateway (session mgmt, broadcast)
│   Gateway       │
└────────┬────────┘
         │ pybind11 (in-process)
┌────────▼────────┐
│  C++ Engine     │  ← Matching engine, LOB, Positions, P&L
│   (libmmg)      │
└─────────────────┘
```

### Tech Stack

- **Frontend**: Flutter Web (Material Design 3)
- **Gateway**: Python 3.11 + FastAPI + Uvicorn + WebSockets
- **Engine**: C++17 + pybind11 (in-process binding)
- **Build**: CMake, Docker, GitHub Actions
- **Deploy**: Docker Compose, Nginx reverse proxy

## 📦 Project Structure

```
.
├── engine/              # C++ matching engine
│   ├── include/mmg/     # Public headers
│   ├── src/             # Implementation
│   ├── bindings/        # pybind11 Python bindings
│   ├── tests/           # Unit tests (Google Test)
│   └── CMakeLists.txt
├── gateway/             # Python FastAPI WebSocket server
│   ├── app/             # Application code
│   │   ├── main.py
│   │   ├── session_manager.py
│   │   └── ws_handler.py
│   ├── tests/           # Python tests
│   └── requirements.txt
├── frontend/            # Flutter web app
│   ├── lib/
│   │   ├── screens/     # Lobby, Terminal, Console
│   │   ├── widgets/     # Price ladder, positions panel
│   │   ├── models/      # Data models
│   │   └── services/    # WebSocket service
│   └── pubspec.yaml
├── scripts/             # Dev and build scripts
│   ├── dev_up.sh        # Start development environment
│   ├── build_all.sh     # Production build
│   └── test_all.sh      # Run all tests
├── docker/              # Docker configuration
│   ├── Dockerfile.engine
│   ├── Dockerfile.gateway
│   ├── Dockerfile.nginx
│   └── nginx.conf
├── .github/workflows/   # CI/CD pipelines
└── docker-compose.yml   # Orchestration
```

## 🚀 Quick Start

### Prerequisites

- **C++ Build**: CMake 3.15+, C++17 compiler (GCC 9+ or Clang 10+)
- **Python**: Python 3.11+, pip
- **Flutter**: Flutter 3.16+ (for web)
- **Docker** (optional): For containerized deployment

### Local Development (No Docker)

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/themarketmakinggame.git
   cd themarketmakinggame
   ```

2. **Run the development script**
   ```bash
   chmod +x scripts/dev_up.sh
   ./scripts/dev_up.sh
   ```

   This script will:
   - Build the C++ engine
   - Set up Python virtual environment
   - Install dependencies
   - Start the gateway on `http://localhost:8000`
   - Start Flutter web on `http://localhost:3000`

3. **Access the application**
   - Frontend: http://localhost:3000
   - Gateway API: http://localhost:8000
   - API Docs: http://localhost:8000/docs

### Manual Setup

#### 1. Build C++ Engine

```bash
cd engine
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_PYTHON_BINDINGS=ON ..
make -j$(nproc)
ctest  # Run tests
cd ../..
```

#### 2. Setup Python Gateway

```bash
cd gateway
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt

# Copy engine binary
cp ../engine/build/mmg_engine*.so .  # or .dylib on macOS

# Run gateway
python -m app.main
```

#### 3. Run Flutter Frontend

```bash
cd frontend
flutter pub get
flutter run -d web-server --web-port 3000
```

## 🐳 Docker Deployment

### Build and Run with Docker Compose

1. **Build the engine first**
   ```bash
   ./scripts/build_all.sh
   ```

2. **Build Docker images**
   ```bash
   docker-compose build
   ```

3. **Start services**
   ```bash
   docker-compose up -d
   ```

4. **Access the application**
   - Application: http://localhost
   - WebSocket: ws://localhost/ws

5. **View logs**
   ```bash
   docker-compose logs -f
   ```

6. **Stop services**
   ```bash
   docker-compose down
   ```

### Production Deployment

For production deployment on a VPS (Lightsail, Hetzner, etc.):

1. **Install Docker and Docker Compose** on your server

2. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/themarketmakinggame.git
   cd themarketmakinggame
   ```

3. **Build everything**
   ```bash
   ./scripts/build_all.sh
   docker-compose build
   ```

4. **Configure SSL (Let's Encrypt)**
   ```bash
   # Install certbot
   sudo apt install certbot python3-certbot-nginx
   
   # Get certificate
   sudo certbot certonly --standalone -d yourdomain.com
   
   # Update nginx.conf with SSL config
   # Mount certificates in docker-compose.yml
   ```

5. **Start with compose**
   ```bash
   docker-compose up -d
   ```

6. **Set up automatic restarts**
   ```bash
   docker-compose restart unless-stopped
   ```

## 🎮 How to Play

### For Exchange Host

1. **Create a room** from the lobby
2. **Add instruments**:
   - SCALAR: Underlying asset (e.g., "BTC")
   - CALL/PUT: Options with strike price
3. **Monitor trading** activity
4. **Settle instruments** at end of session
5. **Export CSV data** for analysis

### For Traders

1. **Join a room** with room code
2. **Select instrument** from the list
3. **Place orders**:
   - Click on price ladder to trade
   - Use order entry dialog for advanced options
   - Hotkeys: ESC = cancel all
4. **Monitor positions** and P&L
5. **Compete** for best P&L on leaderboard

## 📊 WebSocket API

### Client → Server

```json
// Join room
{"op": "join", "room": "ABC123", "name": "Alice", "role": "trader"}

// New order
{"op": "order_new", "inst": 1, "side": "buy", "price": 100.0, "qty": 10, "tif": "GFD"}

// Cancel order
{"op": "cancel", "order_id": 12345}

// Cancel all
{"op": "cancel_all"}

// Settle (exchange only)
{"op": "settle", "inst": 1, "value": 105.0}
```

### Server → Client

```json
// Join acknowledgment
{"type": "join_ack", "user_id": 1, "role": "trader", "resume_token": "..."}

// Market data update (20Hz)
{"type": "md_inc", "inst": 1, "bids": [[100.0, 50]], "asks": [[101.0, 30]]}

// Fill notification
{"type": "fill", "order_id": 12345, "price": 100.0, "qty": 10}

// Position update
{"type": "positions", "positions": [{"inst": 1, "qty": 100, "vwap": 100.0}]}

// P&L update
{"type": "pnl", "pnl": 123.45}
```

## 🧪 Testing

### Run All Tests

```bash
./scripts/test_all.sh
```

### C++ Engine Tests

```bash
cd engine/build
ctest --output-on-failure
```

### Python Gateway Tests

```bash
cd gateway
source venv/bin/activate
pytest tests/ -v
```

### Flutter Tests

```bash
cd frontend
flutter test
```

### Acceptance Tests

```bash
cd gateway/tests
python test_e2e.py
```

## 📈 Performance

- **Matching latency**: < 10μs (in-process C++)
- **WebSocket latency**: ~1-5ms (local network)
- **Market data rate**: 20Hz per instrument
- **Order rate limit**: 50 orders/sec per user
- **Memory usage**: ~100MB for 20 users, 10 instruments

## 🛠️ Development

### Code Style

- **C++**: Google C++ Style Guide
- **Python**: PEP 8, Black formatter
- **Flutter**: Effective Dart

### Adding New Features

1. **New instrument type**: Update `InstrumentType` enum in `types.h` and settlement logic in `engine.cpp`
2. **New order type**: Add to `TimeInForce` enum and implement matching logic in `order_book.cpp`
3. **New UI screen**: Create in `frontend/lib/screens/` and add route in `main.dart`

### Debugging

- **C++ Engine**: Use `gdb` or `lldb` with debug build
- **Python Gateway**: Set `log_level="debug"` in `main.py`
- **Flutter**: Use DevTools (`flutter run --profile`)

## 🐛 Troubleshooting

### Engine build fails

```bash
# Install missing dependencies
sudo apt install build-essential cmake python3-dev

# For macOS
brew install cmake python
```

### Python binding not found

```bash
# Make sure engine is built with bindings
cd engine/build
cmake -DBUILD_PYTHON_BINDINGS=ON ..
make

# Copy to gateway
cp mmg_engine*.so ../../gateway/
```

### Flutter web not starting

```bash
# Check Flutter installation
flutter doctor

# Enable web
flutter config --enable-web

# Clear cache
flutter clean
flutter pub get
```

### WebSocket connection refused

- Check gateway is running on port 8000
- Update WebSocket URL in `frontend/lib/screens/lobby_screen.dart`
- Check firewall settings

## 📝 License

MIT License - See LICENSE file for details

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📧 Contact

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Email**: your.email@example.com

## 🙏 Acknowledgments

- Google Test for C++ testing
- FastAPI for Python web framework
- Flutter for cross-platform UI
- pybind11 for Python/C++ bindings

## 📚 Documentation

- [Architecture Overview](docs/architecture.md)
- [API Reference](docs/api.md)
- [Deployment Guide](docs/deployment.md)
- [Trading Rules](docs/trading.md)

---

**Built with ❤️ for real-time trading enthusiasts**

