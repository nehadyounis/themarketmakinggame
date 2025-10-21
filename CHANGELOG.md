# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-01

### Added
- Initial release of Market Making Game MVP
- C++ matching engine with in-memory order book
- Python FastAPI WebSocket gateway
- Flutter web frontend with Material Design 3
- Support for SCALAR and OPTIONS (Call/Put) instruments
- Real-time position and P&L tracking
- Multi-user room-based sessions
- Lobby, Trading Terminal, and Exchange Console screens
- Click-trading price ladder UI
- Order types: Limit (GFD), IOC, Post-Only
- Risk limits per user
- CSV export for session data
- Docker deployment configuration
- CI/CD with GitHub Actions
- Comprehensive test suite
- Development and build scripts

### Features
- **Matching Engine**
  - FIFO price-time priority
  - Continuous matching
  - Position tracking with VWAP
  - Realized/unrealized P&L calculation
  - Settlement for scalars and options
  - Market data snapshots

- **Gateway**
  - WebSocket JSON protocol
  - Session management with room codes
  - Broadcast market data at 20Hz
  - Fill notifications
  - User authentication with resume tokens
  - Rate limiting (50 orders/sec per user)
  - Automatic CSV export on session close

- **Frontend**
  - Responsive web UI
  - Price ladder with click trading
  - Real-time market data updates
  - Position and P&L panel
  - Order entry dialog
  - Instrument management (Exchange)
  - Leaderboard screen
  - Keyboard shortcuts (ESC = cancel all)

### Performance
- Matching latency: < 10μs
- WebSocket latency: 1-5ms
- Market data rate: 20Hz per instrument
- Memory usage: ~100MB for 20 users

### Deployment
- Docker Compose support
- Nginx reverse proxy
- Let's Encrypt SSL ready
- Runs on 1 vCPU/2GB VM

## [Unreleased]

### Planned
- Binary WebSocket protocol for lower latency
- Per-session child process mode
- SQLite database option
- Advanced order types (Stop, Trailing Stop)
- Market maker incentives
- Historical chart widgets
- Mobile app (iOS/Android)
- Multi-room management
- Admin dashboard
- Analytics and reporting

