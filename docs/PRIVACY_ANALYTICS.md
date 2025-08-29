# Privacy-Preserving Analytics for SecureBlog

## Overview
SecureBlog uses Cloudflare's edge analytics which are privacy-preserving by design. NO client-side JavaScript or tracking pixels are used.

## Metrics Collected (Server-Side Only)

### 1. **Aggregate Traffic Metrics**
- **Page views** - Total requests per URL path
- **Unique visitors** - Estimated via privacy-preserving counting (no cookies)
- **Geographic distribution** - Country/region level only (no city-level data)
- **Response times** - Server-side performance metrics

### 2. **Technical Metrics**
- **HTTP status codes** - 200, 404, etc. distributions
- **Cache hit ratios** - CDN effectiveness
- **Bandwidth usage** - Aggregate data transfer
- **Bot vs human traffic** - Via User-Agent analysis

### 3. **Content Performance**
- **Popular pages** - Ranked by view count
- **Entry/exit pages** - First and last pages in aggregate
- **Time patterns** - Hourly/daily traffic patterns

## What We DON'T Collect

❌ **No Personal Data**
- No IP addresses stored
- No user IDs or fingerprinting
- No cookies or localStorage
- No cross-site tracking

❌ **No Behavioral Tracking**
- No mouse movements
- No scroll depth
- No click tracking
- No session recording

❌ **No Third-Party Data**
- No Google Analytics
- No Facebook Pixel
- No advertising networks
- No data brokers

## Implementation

### Cloudflare Workers Analytics
```javascript
// Edge analytics in worker.js
addEventListener('fetch', event => {
  // Log aggregate metrics only
  const metrics = {
    timestamp: Date.now(),
    path: new URL(event.request.url).pathname,
    country: event.request.cf?.country || 'XX',
    cacheStatus: event.response.headers.get('cf-cache-status'),
    responseTime: Date.now() - start
  };
  
  // Send to privacy-preserving aggregator
  // No user-identifiable information
  logMetrics(metrics);
});
```

### Data Retention
- **Raw logs**: Never stored
- **Aggregate metrics**: 30 days
- **Reports**: Generated weekly, kept for 90 days

### GDPR/CCPA Compliance
- ✅ No personal data collected = no consent needed
- ✅ No data to delete upon request
- ✅ No data to export for portability
- ✅ Privacy by design and default

## Accessing Analytics

Analytics are available via:
1. Cloudflare dashboard (aggregate only)
2. Weekly email reports (if configured)
3. API endpoint: `/api/analytics` (returns JSON, no auth required as data is public)

## Privacy Guarantee

Our analytics are designed to answer:
- "How many people visited?"
- "Which content is popular?"
- "Is the site performing well?"

NOT designed to answer:
- "Who visited?"
- "What did specific users do?"
- "How can we track users?"

## Verification

You can verify our privacy claims:
1. Check network tab - no analytics requests
2. Check cookies - none set
3. Check localStorage - empty
4. View page source - no tracking scripts
5. Run privacy tools (uBlock Origin, Privacy Badger) - no blocks

## Contact

Questions about analytics privacy? Open an issue on GitHub.