# 🚀 SecureBlog Quick Start

## Get Started in 5 Minutes

### 1. Clone from GitHub
```bash
git clone https://github.com/YOUR_USERNAME/secureblog.git
cd secureblog
```

### 2. Install Go (if needed)
- Download from: https://go.dev/dl/
- Version 1.21 or higher

### 3. Build and Run Locally
```bash
# Download dependencies
go mod download

# Build the blog
go run cmd/main_v2.go -content=content -output=build

# View locally (Python)
cd build && python -m http.server 8000

# Or with Node.js
npx serve build
```

Open http://localhost:8000

### 4. Deploy to Production

**Option A: Cloudflare Pages (Recommended)**
```bash
./launch.sh
```
Follow the interactive prompts.

**Option B: Netlify**
```bash
# Install Netlify CLI
npm install -g netlify-cli

# Deploy
netlify init
netlify deploy --prod --dir=build
```

**Option C: GitHub Pages**
```bash
# Push to gh-pages branch
git subtree push --prefix build origin gh-pages
```

## Project Structure
```
secureblog/
├── content/posts/      # Your blog posts (Markdown)
├── templates/          # HTML templates (customizable)
├── plugins/            # Feature plugins
├── build/             # Generated static site
└── launch.sh          # Deployment wizard
```

## Writing Posts

Create a new file in `content/posts/`:

```markdown
# Your Post Title

Write your content in Markdown.

- Supports all standard markdown
- Automatically secured
- No JavaScript needed
```

Then rebuild:
```bash
go run cmd/main_v2.go
```

## Features

✅ **Zero JavaScript** - Maximum security by design
✅ **Privacy-First Analytics** - Cloudflare edge metrics
✅ **Plugin Architecture** - Extend with custom plugins
✅ **Transparency Dashboard** - Public stats at `/stats.html`
✅ **Maximum Security** - CSP, HSTS, integrity hashing
✅ **Fast** - Pure HTML/CSS, instant loads

## Customization

### Change Theme
Edit `templates/index.html` and `templates/post.html`

### Add Analytics
1. Get Cloudflare API token
2. Add to `config.yaml`:
```yaml
plugins:
  cloudflare-analytics:
    cf_zone_id: "your-zone-id"
    cf_api_key: "your-token"
```

### Create Custom Plugin
See `plugin.md` for development guide.

## Security Verification

After deployment, verify security:
- https://securityheaders.com (should score A+)
- https://observatory.mozilla.org
- Check browser DevTools → Network (no JS files)

## Support

- Documentation: `/docs`
- Issues: GitHub Issues
- Example site: https://secureblog-demo.pages.dev

## License

MIT - Use freely for any purpose.

---

**Ready to launch the most secure blog on the internet? Run `./launch.sh`!**