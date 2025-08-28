# Ultra-Secure Blog Generator

A maximum-security static blog generator written in Go with zero JavaScript, no cookies, and no tracking.

## Security Features

- **Zero JavaScript** - No XSS attack surface
- **No Cookies** - No session hijacking possible
- **No External Dependencies** - No supply chain attacks
- **Content Integrity** - SHA256 hashes for all content
- **Strict CSP** - Content Security Policy blocks all vectors
- **Static HTML Only** - No server-side execution
- **Memory Safe** - Written in Go
- **Signed Builds** - Integrity verification for deployments

## Quick Start

```bash
# Install dependencies
go mod tidy

# Create your first post
echo "# My First Post" > content/posts/my-first-post.md

# Build the blog
make build

# Verify integrity
make verify

# Test locally
make serve
```

## Production Deployment

1. Build the blog:
```bash
make build
```

2. Deploy to your server:
```bash
./deploy.sh user@yourserver.com /var/www/blog
```

3. Configure Nginx with the provided `nginx.conf`

## Security Headers

The blog automatically generates security headers for maximum protection:

- Content-Security-Policy: `default-src 'none'`
- X-Frame-Options: `DENY`
- X-Content-Type-Options: `nosniff`
- Strict-Transport-Security: HSTS with preload
- Plus many more...

## File Structure

```
secureblog/
├── cmd/main.go           # Main application
├── internal/
│   ├── builder/          # Site generator
│   └── security/         # Security utilities
├── content/posts/        # Your blog posts (Markdown)
├── templates/            # HTML templates
├── build/                # Generated static site
└── nginx.conf           # Production web server config
```

## Commands

- `make build` - Build the static site
- `make clean` - Remove build artifacts
- `make verify` - Verify build integrity
- `make serve` - Test locally
- `make audit` - Run security audit
- `make dev` - Development mode with auto-rebuild

## Writing Posts

Create Markdown files in `content/posts/`:

```markdown
# Post Title

Your content here...
```

The generator will automatically:
- Convert to secure HTML
- Generate content hashes
- Add security headers
- Create RSS feed

## Maximum Security Deployment

1. Build in isolated environment (Docker/VM)
2. Verify integrity before deployment
3. Use provided Nginx configuration
4. Enable HTTPS only (no HTTP)
5. Set up fail2ban for rate limiting
6. Regular security updates

## License

MIT