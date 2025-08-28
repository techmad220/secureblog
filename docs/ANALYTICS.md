# Privacy-First Analytics with Cloudflare

SecureBlog uses Cloudflare's edge analytics for privacy-preserving statistics - no JavaScript, no cookies, no tracking.

## Why Cloudflare Analytics?

- **Zero client-side tracking** - All metrics collected at edge level
- **No JavaScript injection** - Maintains zero-JS principle
- **No cookies/fingerprinting** - Completely anonymous
- **GDPR/CCPA compliant** - No personal data collection
- **Free tier sufficient** - Basic metrics without cost

## What You Get (Free Plan)

### Traffic Metrics
- Page views
- Unique visitors
- Bandwidth served
- Cache hit ratio

### Security Insights
- Threats blocked
- Bot requests filtered
- DDoS mitigation stats
- WAF rule matches

### Geographic Data
- Country breakdown
- ASN distribution
- No IP addresses stored

### Performance
- Response codes (2xx, 3xx, 4xx, 5xx)
- Origin vs cache served
- Bandwidth saved

## Setup Instructions

### 1. Configure Cloudflare

1. Add your domain to Cloudflare (free plan)
2. Enable proxy (orange cloud) in DNS settings
3. Get your Zone ID from Overview page
4. Create API token with `Zone:Analytics:Read` permission

### 2. Configure SecureBlog

Add to `config.yaml`:

```yaml
plugins:
  cloudflare-analytics:
    enabled: true
    cf_zone_id: "your-zone-id-here"
    cf_api_key: "your-api-token-here"  # Store securely!
    public_stats: true  # Enable public stats page
```

### 3. Environment Variables (Recommended)

Instead of config file, use environment variables:

```bash
export CF_ZONE_ID="your-zone-id"
export CF_API_KEY="your-api-token"

# Build with analytics
./secureblog -content=content -output=build
```

### 4. Build and Deploy

```bash
# Build site with stats page
make build

# Stats will be at /stats.html
# Updates on each build
```

## Public Stats Page

The plugin generates a public `/stats.html` page showing:

- 30-day traffic overview
- Threats blocked
- Bandwidth served
- Privacy notice

No personal or sensitive data is exposed.

## Privacy Notice Template

Add to your privacy policy:

```markdown
## Analytics

This site uses Cloudflare's edge analytics to understand traffic patterns.

What we collect:
- Aggregated page views
- Geographic regions (country-level)
- Threat detection metrics

What we DON'T collect:
- Individual visitor tracking
- IP addresses
- Cookies or browser fingerprints
- Personal information
- Behavior tracking

All metrics are collected at Cloudflare's edge servers before reaching our site. No tracking code runs in your browser.
```

## Advanced Configuration

### Custom Stats Page

Override the default template by creating `templates/stats.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Blog Statistics</title>
</head>
<body>
    <h1>Traffic Statistics</h1>
    {{.PageViews}} views
    {{.UniqueVisitors}} visitors
    <!-- Customize as needed -->
</body>
</html>
```

### API Rate Limits

- Free plan: 1000 requests/day
- Build caching: Stats update once per build
- Consider daily builds via cron/CI

### Exclude Paths

Configure paths to exclude from stats:

```yaml
plugins:
  cloudflare-analytics:
    exclude_paths:
      - /admin
      - /api
      - /private
```

## What You DON'T Get

Without client-side JavaScript:
- Time on page
- Scroll depth
- User flows
- Session recording
- A/B testing

**This is by design** - privacy over detailed metrics.

## Cloudflare Pro ($20/month)

Adds:
- Longer data retention (30 → 365 days)
- More granular filtering
- Bot score analysis
- Advanced security analytics

For most blogs, free tier is sufficient.

## Transparency Dashboard

Create a public dashboard showing:

```markdown
### This Month's Statistics

- **Privacy Protected Visitors**: 10,543
- **Pages Served**: 45,231
- **Threats Blocked**: 1,337
- **Carbon Saved**: 127kg (via CDN caching)
- **Average Response Time**: 23ms

*All statistics are anonymous and aggregated.*
*No individual tracking or cookies used.*
```

## Security Considerations

1. **API Token Storage**
   - Never commit tokens to git
   - Use environment variables
   - Or use CI/CD secrets

2. **Build-Time Only**
   - Stats fetched during build
   - No runtime API calls
   - No client-side requests

3. **Data Minimization**
   - Only show aggregated data
   - Round numbers to prevent fingerprinting
   - Update infrequently (daily max)

## FAQ

**Q: Is this GDPR compliant?**
A: Yes, no personal data is collected or processed.

**Q: Can visitors opt out?**
A: No need - there's nothing to opt out of. No tracking occurs.

**Q: How accurate are the numbers?**
A: Very accurate for human traffic. Bot filtering may vary.

**Q: Can I use Google Analytics instead?**
A: Not without adding JavaScript and compromising the zero-JS principle.

**Q: What about self-hosted analytics?**
A: Consider server log analysis (GoAccess, AWStats) as an alternative.

## Alternative: Log Analysis

If you prefer not using Cloudflare:

```bash
# Parse server logs with GoAccess
goaccess /var/log/nginx/access.log \
  -o /var/www/stats.html \
  --log-format=COMBINED \
  --real-time-html
```

This maintains zero-JS while providing analytics.

## Summary

Cloudflare Analytics provides privacy-respecting metrics without compromising SecureBlog's security principles. You get the numbers that matter while your readers enjoy complete privacy.

**The best tracking is no tracking.**