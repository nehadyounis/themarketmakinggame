# Contributing to Market Making Game

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing.

## Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/yourusername/themarketmakinggame.git
   cd themarketmakinggame
   ```

2. **Set up development environment**
   ```bash
   ./scripts/dev_up.sh
   ```

3. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Code Style

### C++
- Follow Google C++ Style Guide
- Use clang-format for formatting
- Write unit tests for new features
- Document public APIs with Doxygen comments

### Python
- Follow PEP 8
- Use Black for formatting: `black gateway/`
- Use type hints
- Write docstrings for functions and classes
- Maintain test coverage above 80%

### Flutter/Dart
- Follow Effective Dart guidelines
- Use `flutter format` for formatting
- Write widget tests for UI components
- Use meaningful variable names

## Testing

Run all tests before submitting:

```bash
./scripts/test_all.sh
```

### C++ Tests
```bash
cd engine/build
ctest --output-on-failure
```

### Python Tests
```bash
cd gateway
pytest tests/ -v --cov=app
```

### Flutter Tests
```bash
cd frontend
flutter test
```

## Commit Messages

Use conventional commit format:

- `feat: add new feature`
- `fix: resolve bug`
- `docs: update documentation`
- `test: add tests`
- `refactor: restructure code`
- `perf: improve performance`
- `ci: update CI/CD`

Example:
```
feat: add IOC order support to matching engine

- Implement immediate-or-cancel order type
- Add unit tests for IOC matching
- Update API documentation
```

## Pull Request Process

1. **Update documentation** if adding features
2. **Add tests** for new functionality
3. **Run linters** and fix any issues
4. **Update CHANGELOG.md** with your changes
5. **Submit PR** with clear description

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings
```

## Architecture Guidelines

### Adding New Features

#### New Instrument Type
1. Update `InstrumentType` enum in `engine/include/mmg/types.h`
2. Implement settlement logic in `engine/src/engine.cpp`
3. Update Python bindings in `engine/bindings/python_bindings.cpp`
4. Add UI support in Flutter
5. Write tests

#### New Order Type
1. Update order types in `engine/include/mmg/types.h`
2. Implement matching logic in `engine/src/order_book.cpp`
3. Update gateway handlers in `gateway/app/ws_handler.py`
4. Add UI controls in Flutter
5. Write tests

#### New UI Screen
1. Create screen in `frontend/lib/screens/`
2. Add route in `frontend/lib/main.dart`
3. Add navigation links
4. Write widget tests

## Performance Considerations

- **Engine**: Aim for < 10μs matching latency
- **Gateway**: Keep WebSocket latency < 5ms
- **Frontend**: Maintain 60 FPS for animations
- **Memory**: Monitor memory usage for long sessions

## Security

- Never commit secrets or API keys
- Use environment variables for configuration
- Sanitize user inputs
- Rate limit API endpoints
- Validate all data from clients

## Documentation

- Update README.md for user-facing changes
- Add inline comments for complex logic
- Update API documentation
- Create examples for new features

## Questions?

- Open a discussion on GitHub
- Join our Discord community
- Email: dev@marketmakinggame.com

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing! 🎉

