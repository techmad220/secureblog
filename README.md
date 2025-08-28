# SecureBlog - Ultra-Hardened Static Blog Platform

A maximum-security static blog generator with **plugin-based architecture**, zero JavaScript, and defense-in-depth security. Built for paranoid perfectionists who want bulletproof hosting.

## 🔒 Security Architecture

### ⚡ CRITICAL: Latest Security Hardening
- **NO-JS CI Guard** - Automated blocking of ANY JavaScript (enforced on every commit)
- **Origin Elimination** - Cloudflare Pages deployment removes ALL server exposure
- **Supply Chain Lock** - Keyless Cosign + SLSA provenance on every build
- **Ultra-Hardened Nginx** - GET/HEAD only, 1KB limit, TLS 1.3 only
- **Systemd Sandboxing** - Full privilege drop, memory protection, capability restrictions

### Core Security Features
- **Zero JavaScript Policy** - ENFORCED by `.scripts/nojs_guard.sh` in CI
- **Plugin-Based Security** - Modular, auditable security components
- **Content Integrity** - SHA-256 manifest with Cosign attestation
- **SLSA Provenance** - Cryptographic proof of build origin (keyless)
- **OIDC Deployment** - No long-lived credentials ANYWHERE
- **Privacy Analytics** - Server-side only, anonymized, GDPR-compliant
- **Immutable Infrastructure** - CDN-only serving, no origin exposure

### Defense Layers
1. **CI/CD** - NO-JS guard, staticcheck, link verification, supply chain attestation
2. **Build Time** - Reproducible builds, dependency scanning, integrity manifest
3. **Deploy Time** - OIDC-only auth, signed artifacts, provenance verification
4. **Runtime** - Full CSP, read-only serving, 1KB request limit
5. **Edge** - Cloudflare Workers/Pages (no origin server needed)
6. **Monitoring** - Privacy-preserving analytics, automated security audits

## Quick Start

```bash
# Clone and setup
git clone https://github.com/techmad220/secureblog
cd secureblog

# Build with security features
make -f Makefile.security build

# CRITICAL: Verify NO-JS policy (blocks at CI if fails)
bash .scripts/nojs_guard.sh

# Run full security audit
./scripts/security-audit.sh

# Deploy to Cloudflare Pages (no origin server!)
# Configure CF_API_TOKEN and CF_ACCOUNT_ID in GitHub Secrets
# Then just: git push origin main
```

## 🚀 Deployment Options

### Option 1: Cloudflare Pages (RECOMMENDED - No Origin Server!)
```bash
# Set secrets in GitHub:
# - CF_API_TOKEN
# - CF_ACCOUNT_ID

# Auto-deploys on push to main via .github/workflows/deploy-pages.yml
git push origin main
```

### Option 2: Ultra-Hardened Self-Hosted Nginx
```bash
# Use the ultra-hardened config (GET/HEAD only, 1KB limit)
sudo cp nginx-ultra-hardened.conf /etc/nginx/sites-available/secureblog
sudo ln -s /etc/nginx/sites-available/secureblog /etc/nginx/sites-enabled/

# Apply systemd sandboxing
sudo mkdir -p /etc/systemd/system/nginx.service.d/
sudo cp systemd/nginx.service.d/hardening.conf /etc/systemd/system/nginx.service.d/
sudo systemctl daemon-reload
sudo systemctl restart nginx
```

### Option 3: CDN with Workers
```bash
# Deploy to Cloudflare Workers + R2
npx wrangler deploy
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

## ✅ Security Status

| Layer | Protection | Status |
|-------|------------|--------|
| **Regression** | NO-JS CI Guard (`.scripts/nojs_guard.sh`) | ✅ ACTIVE |
| **Supply Chain** | Keyless Cosign + SLSA Provenance | ✅ ACTIVE |
| **Origin** | Cloudflare Pages (no server) | ✅ AVAILABLE |
| **Build** | Reproducible + Integrity Manifest | ✅ ACTIVE |
| **Runtime** | GET/HEAD only, 1KB limit, TLS 1.3 | ✅ CONFIGURED |
| **Systemd** | Full sandboxing + capability drop | ✅ CONFIGURED |
| **Headers** | Complete CSP, HSTS preload, all headers | ✅ ACTIVE |

## 📊 Security Guarantees

- **No JavaScript** - ENFORCED BY CI (cannot merge JS code)
- **No Cookies** - Stateless architecture
- **No Tracking** - Privacy by design
- **No Database** - Static files only
- **No Origin Server** - CDN-only option available
- **No Long-Lived Keys** - OIDC everywhere
- **Signed Artifacts** - Cryptographic provenance on every build
- **Immutable Deploys** - Content integrity verified

## License

MIT