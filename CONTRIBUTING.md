# Contributing to SecureBlog

Thank you for considering contributing to SecureBlog! We welcome contributions that enhance security, add useful plugins, or improve documentation.

## Security First

This project prioritizes security above all else. Any contribution must:

1. **Not introduce JavaScript** - Zero JS policy is non-negotiable
2. **Not add external dependencies** without review
3. **Not weaken security headers** or CSP policies
4. **Include security considerations** in PR description

## How to Contribute

### Reporting Security Issues

**DO NOT** open public issues for security vulnerabilities. Email security@example.com with:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Bug Reports

Open an issue with:
- Clear description
- Steps to reproduce
- Expected vs actual behavior
- Environment details

### Feature Requests

Open an issue describing:
- The problem you're solving
- Proposed solution
- Security implications
- Alternative approaches considered

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-plugin`)
3. Make your changes
4. Add tests if applicable
5. Update documentation
6. Commit with descriptive message
7. Push to your fork
8. Open a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/secureblog.git
cd secureblog

# Install Go 1.21+
# Download from https://go.dev

# Get dependencies
go mod download

# Run tests
go test ./...

# Build
go build -o secureblog cmd/main_v2.go

# Test your changes
./secureblog -content=content -output=build
```

## Plugin Development

See [plugin.md](plugin.md) for plugin development guide.

### Plugin Guidelines

1. **Security by default** - Strict defaults, opt-in for less secure options
2. **No network calls** during build
3. **Validate all input**
4. **Document configuration**
5. **Include tests**

## Code Style

- Use `gofmt` for formatting
- Follow [Effective Go](https://go.dev/doc/effective_go)
- Comment exported functions
- Keep functions focused and small
- Prefer clarity over cleverness

## Testing

```bash
# Run all tests
go test ./...

# Run with coverage
go test -cover ./...

# Run security audit
gosec ./...
```

## Documentation

- Update README for user-facing changes
- Update plugin.md for plugin changes
- Include examples for new features
- Document security implications

## License

By contributing, you agree that your contributions will be licensed under the MIT License.