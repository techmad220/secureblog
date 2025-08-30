## What changed?
- [ ] Content only
- [ ] Templates/layout
- [ ] Build/CI

## Security checks (must all be ✅)
- [ ] No-JS guard passed (`security-regression-guard.sh`)
- [ ] Link checker passed (no 4xx/5xx)
- [ ] SBOM generated (SPDX)
- [ ] Cosign signing/attestation succeeded
- [ ] govulncheck/staticcheck/gitleaks clean

## Deployment
- [ ] Dist built reproducibly (`make -f Makefile.security build`)
- [ ] Matches CDN-only pattern (no origin/server bits)