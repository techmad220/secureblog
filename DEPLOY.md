# Deployment Guide

## Recommended: Cloudflare Pages (Free, Secure, Fast)

### Why Cloudflare Pages?
- **Free tier generous** (500 builds/month, unlimited bandwidth)
- **Automatic HTTPS** with certificates
- **Global CDN** included
- **DDoS protection** built-in
- **Analytics included** (what we configured)
- **Zero-config security headers**

### Setup Steps

1. **Push to GitHub**
```bash
git remote add origin https://github.com/YOUR_USERNAME/secureblog.git
git branch -M main
git push -u origin main
```

2. **Connect to Cloudflare Pages**
- Go to [pages.cloudflare.com](https://pages.cloudflare.com)
- Click "Create a project"
- Connect GitHub account
- Select your secureblog repo

3. **Build Configuration**
```yaml
Build command: go run cmd/main_v2.go -content=content -output=build
Build output directory: /build
Go version: 1.21
```

4. **Environment Variables**
```
CF_API_TOKEN = your-cloudflare-token
CF_ZONE_ID = your-zone-id
```

5. **Custom Domain**
- Add your domain in Pages settings
- Cloudflare auto-configures DNS

## Alternative: Netlify (Also Good)

1. **netlify.toml**
```toml
[build]
  command = "go run cmd/main_v2.go"
  publish = "build"

[[headers]]
  for = "/*"
  [headers.values]
    Content-Security-Policy = "default-src 'none'; style-src 'self'; img-src 'self'"
    X-Frame-Options = "DENY"
    X-Content-Type-Options = "nosniff"
```

2. **Deploy**
```bash
# Install Netlify CLI
npm install -g netlify-cli

# Deploy
netlify deploy --prod --dir=build
```

## Alternative: GitHub Pages

1. **Add GitHub Action**
```yaml
name: Deploy to GitHub Pages
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      - run: go run cmd/main_v2.go
      - uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./build
```

## Production Checklist

### Before Launch
- [ ] Remove example post
- [ ] Add real content (3-5 posts ideal)
- [ ] Update site title/description in config
- [ ] Set up custom domain
- [ ] Configure Cloudflare Analytics
- [ ] Test all links
- [ ] Verify RSS feed
- [ ] Check mobile responsive

### Security Verification
- [ ] Run security headers test: securityheaders.com
- [ ] Verify no JS with browser dev tools
- [ ] Check CSP with csp-evaluator.withgoogle.com
- [ ] Test with Mozilla Observatory

### Performance Check
- [ ] PageSpeed Insights (should score 100)
- [ ] WebPageTest.org verification
- [ ] Check total page size (<100KB ideal)

## Post-Launch

1. **Submit to search engines**
   - Google Search Console
   - Bing Webmaster Tools

2. **Share on security communities**
   - Hacker News
   - Reddit /r/netsec
   - Security Twitter/X

3. **Monitor**
   - Weekly stats updates
   - Cloudflare threat reports
   - Reader feedback

## Backup Strategy

```bash
# Multiple remotes
git remote add github https://github.com/USER/secureblog
git remote add gitlab https://gitlab.com/USER/secureblog
git remote add backup https://codeberg.org/USER/secureblog

# Push to all
git push --all github
git push --all gitlab
git push --all backup
```

## Rollback Process

```bash
# Quick rollback if needed
git revert HEAD
git push

# Or reset to specific commit
git reset --hard <commit-hash>
git push --force
```

Your blog will rebuild automatically!