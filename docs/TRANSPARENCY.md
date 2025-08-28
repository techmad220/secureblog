# Transparency Dashboard Setup

Complete guide for automated, privacy-first analytics dashboard using Cloudflare's edge metrics.

## Overview

The transparency dashboard provides public analytics without compromising privacy:

- **Zero JavaScript** - Pure static HTML
- **No cookies** - No client-side tracking
- **Edge metrics only** - Data from Cloudflare's servers
- **Auto-updated weekly** - GitHub Actions automation
- **Fully transparent** - Public stats page

## Architecture

```
Cloudflare Edge → GraphQL API → GitHub Action → Static HTML → Your Site
     ↓                ↓              ↓               ↓            ↓
  Collects      No tracking    Weekly cron    stats.html    Public
   metrics        needed         updates       committed     dashboard
```

## Setup Instructions

### 1. Prerequisites

- Domain proxied through Cloudflare (orange cloud)
- GitHub repository for your blog
- Cloudflare API token with permissions:
  - `Zone:Read`
  - `Analytics:Read`

### 2. Create Cloudflare API Token

1. Go to Cloudflare Dashboard → My Profile → API Tokens
2. Click "Create Token"
3. Use template: "Custom token"
4. Permissions:
   - Zone → Zone → Read
   - Zone → Analytics → Read
5. Zone Resources: Include → Specific zone → Your domain
6. Copy the token (you'll only see it once)

### 3. Add GitHub Secrets

In your GitHub repo → Settings → Secrets → Actions:

```
CF_API_TOKEN = your-cloudflare-api-token
CF_ZONE_ID = your-cloudflare-zone-id
```

Find Zone ID: Cloudflare Dashboard → Your domain → Overview → Zone ID

### 4. Add Files to Repository

```bash
# Stats template with placeholders
templates/stats-template.html

# GitHub Action for weekly updates
.github/workflows/update-stats.yml
```

### 5. Initial Manual Run

1. Go to GitHub → Actions → "Update Analytics Dashboard"
2. Click "Run workflow" → "Run workflow"
3. Wait ~1 minute for completion
4. Check your repo - `stats.html` should be created

### 6. Deployment

The `stats.html` file will be automatically:
- Updated every Sunday at midnight UTC
- Committed to your repository
- Deployed with your regular build process

## How It Works

### Data Collection (Cloudflare Edge)

```javascript
// What Cloudflare collects at edge:
{
  requests: 45231,        // Total HTTP requests
  uniques: 10543,        // Unique IPs (anonymized)
  bytes: 156789000,      // Bandwidth served
  threats: 1337,         // Blocked attacks
  country: "US",         // Geographic region
  cached: 38000          // Served from cache
}
```

### Weekly Update Process

1. **Sunday 00:00 UTC**: GitHub Action triggers
2. **API Call**: Fetches last 7 days from Cloudflare GraphQL
3. **Processing**: Aggregates totals, finds top country
4. **Template**: Replaces placeholders in HTML template
5. **Commit**: Updates `stats.html` in repository
6. **Deploy**: Your existing CI/CD publishes changes

### Privacy Guarantees

What we DON'T collect:
- IP addresses
- User agents
- Cookies
- Session data
- Personal information
- Behavior tracking
- Time on page
- Individual page paths

What we DO show:
- Aggregated request counts
- Approximate unique visitors
- Total bandwidth
- Security metrics
- Top country (no cities)
- Cache performance

## Customization

### Change Update Frequency

Edit `.github/workflows/update-stats.yml`:

```yaml
# Daily at 2 AM UTC
- cron: "0 2 * * *"

# Every Monday and Thursday
- cron: "0 0 * * 1,4"

# Monthly on the 1st
- cron: "0 0 1 * *"
```

### Modify Stats Shown

Edit `templates/stats-template.html`:

```html
<!-- Add new metric -->
<div class="stat-card">
    <span class="stat-value">{{PAGE_VIEWS}}</span>
    <span class="stat-label">Page Views</span>
</div>
```

Then update workflow to populate it.

### Style Changes

The template uses inline CSS for zero dependencies. Modify styles directly in the template.

## Manual Stats Update

```bash
# Trigger manually from GitHub
Actions → Update Analytics Dashboard → Run workflow

# Or via GitHub CLI
gh workflow run update-stats.yml
```

## Troubleshooting

### No Data Returned

- Verify domain is proxied (orange cloud)
- Check API token has Analytics:Read permission
- Ensure Zone ID is correct
- Wait 24h for initial data if new site

### Action Fails

Check error in GitHub Actions log:
- API token expired → Generate new token
- Rate limit → Reduce update frequency
- No changes → Normal if stats unchanged

### Stats Not Updating

1. Check GitHub Actions is enabled
2. Verify secrets are set correctly
3. Manually run workflow to test
4. Check commit permissions

## Advanced Features

### Multiple Zones

```yaml
env:
  CF_ZONE_IDS: "zone1,zone2"
# Modify script to loop through zones
```

### Historical Data

```yaml
# Keep historical records
- name: Archive stats
  run: |
    DATE=$(date +%Y%m%d)
    cp stats.html "archive/stats-${DATE}.html"
    git add archive/
```

### Alerts on Anomalies

```yaml
# Send alert if traffic spikes
- name: Check for anomalies
  run: |
    if [ "$THREATS" -gt 10000 ]; then
      echo "High threat count detected!"
      # Send notification
    fi
```

## Integration with SecureBlog

### Add to Navigation

In your templates:

```html
<nav>
    <a href="/">Home</a>
    <a href="/stats.html">Analytics</a>
    <a href="/feed.xml">RSS</a>
</nav>
```

### Update Sitemap

```xml
<url>
    <loc>/stats.html</loc>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
</url>
```

### Link from Footer

```html
<footer>
    <p>View our <a href="/stats.html">transparency dashboard</a></p>
    <p>Updated weekly • No tracking • Edge metrics only</p>
</footer>
```

## Public Trust Building

### Add to Privacy Policy

```markdown
## Analytics Transparency

We publish our traffic statistics publicly at [/stats.html](/stats.html).

- Updated weekly (Sundays)
- Collected at CDN edge level
- No JavaScript tracking
- No personal data
- Fully open methodology
```

### Verification

Users can verify the no-JS claim:
1. View page source - no analytics scripts
2. Check browser developer tools - no tracking requests
3. Review our GitHub workflow - fully open source

## Benefits

1. **Build Trust** - Show readers you practice what you preach
2. **No Performance Impact** - Zero client-side code
3. **GDPR Compliant** - No personal data processing
4. **Fully Automated** - Set and forget
5. **Cost-Free** - Uses Cloudflare free tier

## Summary

This transparency dashboard provides meaningful analytics while maintaining absolute user privacy. It's the perfect solution for security blogs that need to demonstrate their commitment to privacy-first principles.

**Your readers' privacy is preserved. Your metrics are public. Trust is earned.**