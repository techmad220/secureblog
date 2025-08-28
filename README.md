# SecureBlog - Ultra-Hardened Static Blog Platform

A maximum-security static blog generator with **plugin-based architecture**, zero JavaScript, and defense-in-depth security. Built for paranoid perfectionists who want bulletproof hosting.

## 🔒 Security Architecture

### Core Security Features
- **Zero JavaScript Policy** - Enforced at build, serve, and CDN levels
- **Plugin-Based Security** - Modular, auditable security components
- **Content Integrity** - SHA-256 manifest with Cosign attestation
- **SLSA Provenance** - Reproducible builds with supply chain attestation
- **OIDC Deployment** - No long-lived credentials anywhere
- **Privacy Analytics** - Server-side only, anonymized, GDPR-compliant
- **Immutable Infrastructure** - CDN-only serving, no origin exposure

### Defense Layers
1. **Build Time** - Static analysis, no-JS verification, dependency scanning
2. **Deploy Time** - Integrity verification, OIDC auth, signed manifests
3. **Runtime** - CSP headers, read-only serving, rate limiting
4. **Edge** - Cloudflare Workers with security plugins
5. **Monitoring** - Privacy-preserving analytics, security audits

## Quick Start

```bash
# Clone and setup
git clone https://github.com/techmad220/secureblog
cd secureblog

# Build with security features
make -f Makefile.security build

# Run security audit
./scripts/security-audit.sh

# Deploy to Cloudflare (recommended)
./scripts/deploy-cloudflare.sh
```

## 🚀 Deployment Options

### Option 1: Cloudflare Pages (Recommended)
```bash
# Deploy with OIDC (no API keys needed)
make -f Makefile.security deploy-cloudflare
```

### Option 2: Self-Hosted with Nginx
```bash
# Use hardened systemd service
sudo cp secureblog-nginx.service /etc/systemd/system/
sudo cp nginx-hardened.conf /etc/nginx/
sudo systemctl enable --now secureblog-nginx
```

### Option 3: Static CDN Only
```bash
# Build and push to any S3-compatible storage
./scripts/deploy-cloudflare.sh
```

## 🛡️ Security Headers

All responses include comprehensive security headers:

```nginx
Content-Security-Policy: default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
Referrer-Policy: no-referrer
Permissions-Policy: accelerometer=(), battery=(), camera=(), geolocation=(), microphone=()
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: same-origin
```

## 📁 File Structure

```
secureblog/
├── cmd/                      # Main application
├── internal/                 # Core functionality
│   ├── builder/             # Site generator
│   └── security/            # Security utilities
├── plugins/                 # Security plugins (modular)
│   ├── integrity/           # Content integrity verification
│   ├── analytics/           # Privacy-preserving analytics
│   ├── audit/              # Security audit plugins
│   └── deploy/             # Deployment plugins
├── scripts/                 # Automation scripts
│   ├── security-audit.sh   # Comprehensive security scan
│   ├── integrity-verify.sh # Content verification
│   ├── deploy-cloudflare.sh # OIDC deployment
│   └── analytics-aggregator.sh # Privacy analytics
├── .github/workflows/       # CI/CD with security
│   ├── provenance.yml      # SLSA attestation
│   ├── supply-chain.yml   # Dependency security
│   └── deploy.yml         # Secure deployment
├── src/                    # Cloudflare Workers
│   ├── worker.js          # Edge security
│   └── worker-plugins.js  # Plugin system
├── content/posts/          # Your blog posts
├── templates/              # HTML templates (no JS)
├── dist/                   # Generated static site
├── nginx-hardened.conf    # Hardened nginx config
├── secureblog-nginx.service # Systemd security
├── security-headers.conf  # Security headers config
├── wrangler.toml          # Cloudflare config
└── Makefile.security      # Security-focused build

## 🔧 Commands

### Security Operations
- `make -f Makefile.security build` - Secure build with integrity
- `make -f Makefile.security verify` - Verify content integrity
- `make -f Makefile.security audit` - Run security audit
- `make -f Makefile.security deploy` - Deploy with OIDC
- `./scripts/security-audit.sh` - Comprehensive security scan

### Development
- `make -f Makefile.security dev` - Read-only dev server
- `make -f Makefile.security clean` - Clean artifacts
- `make -f Makefile.security sbom` - Generate SBOM

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

## 🔐 Plugin System

All security features are implemented as plugins for easy customization:

### Available Plugins
- **Integrity Plugin** (`plugins/integrity/`) - Content hash verification
- **Analytics Plugin** (`plugins/analytics/`) - Privacy-preserving metrics
- **Security Audit** (`plugins/audit/`) - Automated security checks
- **Deployment** (`plugins/deploy/`) - OIDC and secure deployment

### Creating Custom Plugins
```bash
# Add your plugin to plugins directory
mkdir plugins/my-security-plugin
# Implement plugin interface
# Auto-loaded by build system
```

## 🚨 Security Monitoring

### Automated Audits
```bash
# Run comprehensive security audit
./scripts/security-audit.sh

# Check specific areas
./scripts/security-audit.sh --no-js
./scripts/security-audit.sh --dependencies
./scripts/security-audit.sh --headers
```

### Privacy Analytics
```bash
# Process anonymized logs
./scripts/analytics-aggregator.sh

# Generate monthly reports (no PII)
make -f Makefile.security analytics
```

## 🏗️ Build Security

### Reproducible Builds
- `-trimpath` flag for path independence
- `-mod=readonly` for dependency integrity
- SHA-256 manifest for all files
- Cosign attestation for provenance

### Supply Chain Security
- GitHub Actions with OIDC (no secrets)
- Dependency vulnerability scanning
- SLSA provenance generation
- Signed releases with Sigstore

## 🛠️ Advanced Configuration

### Environment Variables
```bash
# Cloudflare deployment
export CLOUDFLARE_ACCOUNT_ID=xxx
export CF_ZONE_ID=xxx

# Mirror deployment (optional)
export MIRROR_HOST=backup.example.com

# Analytics retention
export RETENTION_DAYS=30
```

### Security Customization
Edit `plugins/*/config.json` to customize:
- CSP policies
- Rate limiting rules
- Analytics privacy levels
- Deployment targets

## 📊 Security Guarantees

- **No JavaScript** - Enforced at every layer
- **No Cookies** - Stateless architecture
- **No Tracking** - Privacy by design
- **No Database** - Static files only
- **No Origin Server** - CDN-only serving
- **Signed Artifacts** - Cryptographic provenance
- **Immutable Deploys** - Content integrity verified

## License

MIT