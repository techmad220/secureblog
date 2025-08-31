# Account Takeover Protection Guide

**Last Updated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Security Level**: CONFIDENTIAL - Authorized Personnel Only

## Executive Summary

This document outlines comprehensive account takeover protection measures for SecureBlog infrastructure accounts including GitHub, Cloudflare, and related services. These measures implement defense-in-depth security to prevent unauthorized access that could compromise deployment integrity.

## Critical Account Security Requirements

### 1. Hardware Security Keys (MANDATORY)

**All accounts MUST use hardware security keys as the primary 2FA method.**

#### Required Setup:
- **Primary Key**: YubiKey 5 Series or equivalent FIDO2/WebAuthn key
- **Backup Key**: Second hardware key stored in secure location
- **Recovery Codes**: Generated and stored in encrypted password manager

#### Implementation Steps:
```bash
# GitHub Account Security
1. Navigate to GitHub Settings > Security
2. Enable 2FA with hardware key as primary method
3. Add backup hardware key
4. Download and securely store recovery codes
5. Remove any SMS-based 2FA methods
6. Enable "Require 2FA for organization" if applicable

# Cloudflare Account Security  
1. Navigate to Cloudflare > My Profile > Authentication
2. Enable 2FA with hardware security key
3. Add backup hardware key
4. Store recovery codes securely
5. Disable SMS/email 2FA fallbacks
```

#### Verification Commands:
```bash
# Test GitHub 2FA requirement
gh auth status --show-token 2>&1 | grep -q "2FA" && echo "✅ GitHub 2FA active"

# Verify no SMS fallback configured
# This requires manual verification in account settings
```

### 2. Single Sign-On (SSO) Integration

**Implement organization-wide SSO for centralized access control.**

#### GitHub SSO Configuration:
```bash
# Required for GitHub Enterprise/Organizations
1. Configure SAML SSO with identity provider
2. Enforce SSO for all organization members  
3. Require re-authentication every 24 hours
4. Enable IP allow-listing for admin operations
5. Set up audit log monitoring
```

#### Cloudflare SSO Configuration:
```bash
# Cloudflare Access/Zero Trust setup
1. Configure Cloudflare Access with identity provider
2. Create access policies for admin panels
3. Enable session timeout (8 hours maximum)
4. Configure IP-based conditional access
5. Set up device certificate requirements
```

### 3. Account Privilege Minimization

**Implement least-privilege access with role-based controls.**

#### GitHub Permissions:
- **Repository Admin**: Only for core maintainers (max 2 people)
- **Write Access**: For active contributors with proven track record
- **Read Access**: For reviewers and external collaborators
- **Deployment Keys**: Read-only, scoped to specific repositories only

#### Cloudflare Permissions:
- **Super Administrator**: Only for emergency use (max 1 account)
- **Administrator**: Domain and security management (max 2 accounts)  
- **DNS Manager**: DNS-only access for operations team
- **Analytics Reader**: Read-only access for monitoring

#### API Token Scoping:
```bash
# GitHub Personal Access Tokens
- Scope: repo, workflow (minimal required)
- Expiration: 90 days maximum
- IP restrictions: Enable if supported
- Regular rotation schedule

# Cloudflare API Tokens
- Zone:Read, Zone:Edit for specific zones only
- Account:Read for billing/usage only
- Expiration: 30 days maximum
- IP restrictions: Enforce deployment IP ranges
```

### 4. DNS Security Hardening

**Protect DNS infrastructure from takeover attempts.**

#### DNSSEC Implementation:
```bash
# Enable DNSSEC for all domains
dig +dnssec secureblog.com | grep RRSIG && echo "✅ DNSSEC active"

# Verify DS record in parent zone
dig +trace secureblog.com DS
```

#### CAA Records Configuration:
```bash
# Certificate Authority Authorization
dig secureblog.com CAA

# Expected output:
# secureblog.com. 300 IN CAA 0 issue "letsencrypt.org"
# secureblog.com. 300 IN CAA 0 issuewild ";"
# secureblog.com. 300 IN CAA 0 iodef "mailto:security@secureblog.com"
```

#### DNS Monitoring:
```bash
# Implement DNS change monitoring
# Set up alerts for:
# - NS record changes
# - MX record modifications  
# - TXT record additions
# - A/AAAA record changes
```

### 5. Token and Key Management

**Secure management of all authentication tokens and keys.**

#### GitHub Tokens:
```bash
# Repository secrets audit
gh secret list --repo secureblog

# Required secrets validation:
COSIGN_PRIVATE_KEY     # Encrypted signing key
CF_API_TOKEN          # Scoped Cloudflare token  
CF_ZONE_ID            # Zone identifier only
```

#### Token Rotation Schedule:
- **GitHub PATs**: Every 90 days
- **Cloudflare API Tokens**: Every 30 days
- **Signing Keys**: Every 365 days (with proper key transition)
- **Recovery Codes**: After each use

#### Secure Storage Requirements:
```bash
# All secrets must be stored using:
1. GitHub Encrypted Secrets (for CI/CD)
2. Hardware security module (for signing keys)
3. Encrypted password manager (for personal access)
4. Air-gapped backup (for recovery codes)

# Prohibited storage methods:
# - Plain text files
# - Version control
# - Unencrypted cloud storage
# - Shared documents
```

### 6. Network Security Controls

**Implement network-level protections against account access.**

#### IP Allow-listing:
```bash
# GitHub organization security
1. Enable IP allow lists for organization
2. Include only trusted office/VPN ranges
3. Require allow-list for Git operations
4. Monitor and alert on policy bypasses

# Cloudflare account security
1. Configure IP-based access rules
2. Block high-risk countries if appropriate
3. Enable bot management for admin panels
4. Set up rate limiting for login attempts
```

#### VPN Requirements:
```bash
# Mandatory VPN for administrative access
1. WireGuard or equivalent enterprise VPN
2. Certificate-based authentication
3. Multi-hop routing for admin operations
4. Kill-switch enabled on all devices
5. Regular connection auditing
```

### 7. Monitoring and Alerting

**Comprehensive monitoring for account security events.**

#### GitHub Security Monitoring:
```bash
# Enable and monitor:
# - Login attempts and locations
# - Permission changes
# - Repository access patterns
# - API token usage
# - Organization member changes
# - Webhook modifications

# Alert thresholds:
# - Login from new location: Immediate
# - Permission elevation: Immediate  
# - Failed 2FA: After 3 attempts
# - Unusual API usage: Based on baseline
```

#### Cloudflare Security Monitoring:
```bash
# Enable and monitor:
# - Account login events
# - DNS record changes
# - SSL certificate changes
# - Firewall rule modifications
# - Worker deployments
# - Analytics access patterns

# Alert destinations:
# - Security team email
# - Slack security channel
# - SMS for critical events
# - PagerDuty for outages
```

### 8. Incident Response Procedures

**Predefined procedures for account compromise scenarios.**

#### Suspected Compromise Response:
```bash
# Immediate Actions (0-15 minutes):
1. Change all passwords immediately
2. Revoke all active sessions
3. Rotate all API tokens and keys
4. Enable additional IP restrictions
5. Review recent activity logs
6. Notify security team

# Investigation Phase (15-60 minutes):
1. Analyze access logs for anomalies
2. Check for unauthorized changes
3. Verify integrity of deployments
4. Review webhook and integration logs
5. Confirm backup systems integrity

# Recovery Phase (1+ hours):
1. Reset all authentication methods
2. Re-issue hardware security keys if needed
3. Update all stored secrets
4. Rebuild compromised systems from known-good state
5. Implement additional monitoring
6. Document lessons learned
```

#### Emergency Contacts:
- **Primary Security Contact**: security@secureblog.com
- **GitHub Enterprise Support**: [Support Case System]
- **Cloudflare Enterprise Support**: [Support Portal]
- **Legal/Compliance Team**: legal@secureblog.com

### 9. Compliance and Audit

**Regular audits and compliance verification.**

#### Monthly Security Review:
```bash
# Account access audit
1. Review all user accounts and permissions
2. Verify 2FA status for all accounts
3. Check for unused/orphaned tokens
4. Validate IP allow-list effectiveness
5. Review login logs for anomalies

# Token and key audit
1. Inventory all active tokens and keys
2. Verify expiration dates and rotation schedule
3. Check for leaked credentials in public repos
4. Validate secure storage compliance
5. Test recovery procedures
```

#### Quarterly Penetration Testing:
```bash
# External security assessment
1. Social engineering resistance testing
2. Account takeover attempt simulation
3. Multi-factor authentication bypass testing
4. Network security control validation
5. Recovery procedure effectiveness testing
```

### 10. Training and Awareness

**Security awareness for all personnel with account access.**

#### Mandatory Training Topics:
- Phishing and social engineering recognition
- Hardware security key usage and care
- Secure password practices
- Incident reporting procedures
- Two-person integrity for critical changes

#### Simulation Exercises:
- Quarterly phishing simulations
- Annual account takeover tabletop exercises
- Emergency response drills
- Recovery procedure testing

## Security Control Validation

### Automated Checks:
```bash
#!/bin/bash
# account-security-check.sh

echo "🔐 Account Security Validation"
echo "=============================="

# Check GitHub 2FA status
if gh auth status 2>&1 | grep -q "2FA"; then
    echo "✅ GitHub 2FA active"
else
    echo "❌ GitHub 2FA not detected"
fi

# Check for hardware key requirement
# Manual verification required

# Verify API token scopes
gh auth status --show-scopes 2>&1 | grep -E "repo|workflow" && echo "✅ GitHub token properly scoped"

# Check Cloudflare token permissions
# Requires CF_API_TOKEN environment variable
if [ -n "$CF_API_TOKEN" ]; then
    curl -H "Authorization: Bearer $CF_API_TOKEN" \
         "https://api.cloudflare.com/client/v4/user/tokens/verify" \
         | jq '.success' | grep -q true && echo "✅ Cloudflare token valid"
fi

echo "Manual verification required for:"
echo "- Hardware security key enrollment"
echo "- Recovery code storage"
echo "- IP allow-list configuration"
echo "- SSO integration status"
```

### Manual Verification Checklist:
- [ ] Hardware security keys enrolled as primary 2FA
- [ ] Backup hardware keys configured and tested
- [ ] Recovery codes generated and securely stored
- [ ] SMS/email 2FA methods disabled
- [ ] IP allow-lists configured and tested
- [ ] API tokens scoped to minimum required permissions
- [ ] Token expiration dates within policy limits
- [ ] SSO integration configured (if applicable)
- [ ] DNSSEC enabled and DS records published
- [ ] CAA records configured correctly
- [ ] Monitoring and alerting systems active
- [ ] Incident response procedures documented and tested
- [ ] Emergency contacts verified and current

## Risk Assessment

### High-Risk Scenarios:
1. **Credential Stuffing**: Mitigated by hardware 2FA and unique passwords
2. **SIM Swapping**: Mitigated by eliminating SMS-based authentication
3. **Phishing**: Mitigated by hardware key requirements and training
4. **Insider Threats**: Mitigated by least-privilege and monitoring
5. **Supply Chain**: Mitigated by token scoping and SLSA attestation

### Residual Risks:
1. **Hardware Key Loss**: Mitigated by backup keys and recovery codes
2. **Social Engineering**: Mitigated by multi-person authorization
3. **Zero-Day Exploits**: Mitigated by defense-in-depth approach
4. **Physical Security**: Mitigated by secure key storage procedures

## Compliance Mapping

### Standards Addressed:
- **NIST Cybersecurity Framework**: All five framework functions implemented
- **ISO 27001**: Access control and incident management requirements
- **SOC 2 Type II**: Security and availability common criteria
- **OWASP ASVS**: Authentication and session management requirements

---

**Document Classification**: CONFIDENTIAL
**Review Schedule**: Quarterly
**Next Review Date**: $(date -d '+3 months' +%Y-%m-%d)
**Authorized Personnel Only** - Do not distribute outside security team