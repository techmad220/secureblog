# Security Hardening Guide - SecureBlog

## Critical Security Layers

### 1. CI/CD Security (Prevents Regressions)
- **NO-JS Guard**: Enforced on every commit via `.scripts/nojs_guard.sh`
- **Static Analysis**: go vet + staticcheck on all code
- **Link Checking**: Broken links fail CI
- **Supply Chain**: go.mod must be tidy, no dirty state

### 2. Provenance & Attestation (Supply Chain)
- **Keyless Signing**: Cosign with OIDC (no long-lived keys)
- **SLSA Provenance**: Cryptographic proof of build origin
- **Artifact Attestation**: site.tar.gz with signed attestation

### 3. Origin Removal (Zero Public Attack Surface)
- **Cloudflare Pages**: Direct CDN deployment, no origin server
- **No SSH/VM**: Eliminates kernel, SSH, and server vulnerabilities
- **Immutable Deploys**: CDN serves static files only

### 4. Nginx Ultra-Hardening (If Self-Hosted)
- **GET/HEAD Only**: No POST, PUT, DELETE
- **1KB Body Limit**: Prevents request smuggling
- **TLS 1.3 Only**: No legacy crypto
- **Immutable Cache**: 365-day cache for assets
- **Strict Headers**: Full CSP, HSTS preload, all security headers

### 5. Systemd Sandboxing
- **No New Privileges**: Can't escalate
- **Memory Protection**: W^X enforced
- **Namespace Isolation**: Network/PID/Mount isolation
- **Minimal Capabilities**: Only CAP_NET_BIND_SERVICE

## Deployment Options

### Option A: Cloudflare Pages (Recommended - No Origin)
```bash
# Set GitHub Secrets:
# - CF_API_TOKEN (Pages write permission)
# - CF_ACCOUNT_ID (Your account ID)

# Deploy automatically on push to main
git push origin main
# GitHub Actions runs deploy-pages.yml
```

### Option B: Self-Hosted with Ultra-Hardened Nginx
```bash
# 1. Copy nginx config
sudo cp nginx-ultra-hardened.conf /etc/nginx/sites-available/secureblog
sudo ln -s /etc/nginx/sites-available/secureblog /etc/nginx/sites-enabled/

# 2. Apply systemd hardening
sudo mkdir -p /etc/systemd/system/nginx.service.d/
sudo cp systemd/nginx.service.d/hardening.conf /etc/systemd/system/nginx.service.d/
sudo systemctl daemon-reload
sudo systemctl restart nginx

# 3. Deploy static files
rsync -avz --delete build/ /var/www/blog/
```

## Verification

### 1. No-JS Policy Check
```bash
bash .scripts/nojs_guard.sh
```

### 2. Verify Provenance
```bash
cosign verify-blob \
  --certificate site.tar.gz.attestation \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  site.tar.gz
```

### 3. Security Headers Test
```bash
curl -I https://yourdomain.com | grep -E "Content-Security|X-Frame"
```

### 4. TLS Test
```bash
testssl.sh --severity HIGH https://yourdomain.com
```

## Security Guarantees

✅ **Build Time**: No JavaScript can ever be introduced (CI blocks it)
✅ **Supply Chain**: All builds have cryptographic provenance
✅ **Runtime**: No origin server exposed (CDN-only)
✅ **Defense in Depth**: Multiple independent security layers
✅ **Zero Trust**: No long-lived credentials anywhere

## Emergency Response

If security incident detected:
1. Rollback via CDN (instant)
2. Check provenance of deployed artifact
3. Run `.scripts/nojs_guard.sh` on suspect content
4. Review GitHub Actions logs for tampering