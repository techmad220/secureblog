# Security Audit Documentation

## What `make audit` Does

The `make audit` command runs a comprehensive security scan of your SecureBlog installation, checking for vulnerabilities, misconfigurations, and security regressions.

## Audit Components

### 1. Static Code Analysis
```bash
gosec ./...
```
- Scans Go code for security vulnerabilities
- Detects: SQL injection, XSS, hardcoded credentials, weak crypto
- Output: JSON report with severity levels

### 2. Dependency Vulnerability Scanning
```bash
govulncheck ./...
```
- Checks all Go dependencies for known CVEs
- Compares against OSV database
- Reports: vulnerable packages, severity, fix versions

### 3. Supply Chain Security
```bash
staticcheck ./...
```
- Analyzes code for bugs and performance issues
- Checks for deprecated/unsafe functions
- Verifies correct use of security APIs

### 4. Secret Detection
```bash
gitleaks detect
```
- Scans for hardcoded secrets, API keys, passwords
- Checks commit history for leaked credentials
- Uses regex patterns for 150+ secret types

### 5. JavaScript Detection
```bash
bash .scripts/security-regression-guard.sh
```
- Ensures NO client-side JavaScript exists
- Checks HTML files for `<script>` tags
- Verifies no inline event handlers
- Blocks `javascript:` protocol URLs

### 6. Content Integrity Verification
```bash
bash scripts/verify-manifest.sh build/
```
- Verifies SHA-256 hashes of all files
- Checks for unauthorized modifications
- Validates signed manifests if present

### 7. Security Headers Check
```bash
grep -r "Content-Security-Policy" build/
```
- Verifies CSP headers are present
- Checks for strict `default-src 'none'`
- Validates other security headers

### 8. Build Reproducibility
```bash
go build -trimpath -buildvcs=false
```
- Ensures builds are reproducible
- Removes local paths from binaries
- Enables verification by third parties

## Running the Audit

### Full Audit
```bash
make audit
# or
make -f Makefile.security audit
```

### Individual Checks
```bash
# Just dependency scanning
make audit-deps

# Just secret scanning  
make audit-secrets

# Just JavaScript check
make audit-nojs

# Just integrity check
make audit-integrity
```

## Understanding Output

### Pass ✅
```
✅ No JavaScript detected
✅ No hardcoded secrets found
✅ All dependencies secure
✅ Content integrity verified
```

### Fail ❌
```
❌ JavaScript found in templates/index.html:42
❌ Vulnerable dependency: golang.org/x/net (CVE-2023-1234)
❌ Hardcoded API key in config.yaml:15
❌ Integrity mismatch: index.html
```

## Audit Frequency

| When | What to Run |
|------|------------|
| Every commit | `make audit-nojs` (fast) |
| Daily | `make audit` (full) |
| Before deploy | `make audit && make verify` |
| After dependency update | `make audit-deps` |

## CI/CD Integration

The audit runs automatically on:
- Every push to main
- Every pull request
- Nightly scheduled runs

See `.github/workflows/test.yml` for configuration.

## Security Thresholds

The audit will **FAIL** if:
- Any client-side JavaScript is detected
- Critical vulnerabilities (CVSS > 7.0) found
- Hardcoded secrets detected
- Content integrity mismatches
- CSP headers missing or weak

## Custom Audit Rules

Add custom checks to `scripts/security-audit.sh`:

```bash
# Example: Check for insecure protocols
echo "→ Checking for insecure protocols..."
if grep -r "http://" content/ --exclude-dir=.git; then
    echo "❌ Insecure HTTP links found"
    exit 1
fi
```

## Fixing Audit Failures

### JavaScript Detected
1. Remove all `<script>` tags
2. Remove inline handlers (`onclick`, etc.)
3. Remove `javascript:` URLs
4. Re-run `make audit-nojs`

### Vulnerable Dependencies
1. Run `go get -u ./...` to update
2. Check for breaking changes
3. Test thoroughly
4. Re-run `make audit-deps`

### Hardcoded Secrets
1. Remove secret from code
2. Use environment variables
3. Run `git filter-branch` if in history
4. Rotate the exposed secret
5. Re-run `make audit-secrets`

### Integrity Failures
1. Rebuild with `make clean build`
2. Re-sign with `make sign`
3. Verify with `make verify`

## Audit Report

Generate a full report:
```bash
make audit-report > audit-$(date +%Y%m%d).txt
```

Report includes:
- Timestamp
- Git commit hash
- All check results
- Remediation suggestions
- Compliance status

## Security Baseline

The audit establishes a security baseline:

```yaml
# .security-baseline.yaml
baseline:
  javascript_count: 0
  vulnerability_count: 0
  secret_count: 0
  weak_crypto_count: 0
  integrity_failures: 0
  
thresholds:
  max_javascript: 0
  max_critical_vulns: 0
  max_high_vulns: 2
  max_medium_vulns: 5
```

## Exceptions

If you must add exceptions (NOT recommended):

```yaml
# .security-exceptions.yaml
exceptions:
  - rule: "G104"  # Unhandled errors
    file: "cmd/main.go"
    line: 42
    reason: "Error intentionally ignored for cleanup"
    expires: "2024-12-31"
    approved_by: "security-team"
```

## Questions?

The audit is designed to be strict. If you're getting false positives or need clarification, open an issue with the `security-audit` label.