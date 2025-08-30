# 🔒 SecureBlog Admin Guide

**WordPress Easy, Fort Knox Secure**

Transform your ultra-secure blog into a user-friendly content management system without compromising security.

## 🚀 Quick Start

```bash
# 1. Start the admin interface
./start-admin.sh

# 2. Open your browser
open http://localhost:3000

# 3. Login
Username: admin
Password: secure123  # Change via ADMIN_PASSWORD env var
```

## ✨ Features Overview

### 📝 **Content Management (WordPress-like)**
- **WYSIWYG Editor**: Write in Markdown with live HTML preview
- **Auto-Save**: Never lose your work (saves every 30 seconds)
- **Drag & Drop Images**: Upload images by dragging into the interface
- **SEO Friendly**: Auto-generates slugs, meta descriptions, tags
- **Draft Management**: Save drafts and publish when ready

### 🎨 **Visual Theme Editor**
- **Live Preview**: See changes instantly as you edit
- **Component-Based**: Edit headers, footers, layouts separately
- **Color Customization**: Visual color pickers for themes
- **Font Selection**: Choose from web-safe font stacks
- **Mobile Responsive**: Automatic responsive design

### 🚀 **One-Click Publishing**
```
Write → Preview → Publish → Deploy
```
All in one streamlined workflow!

### 🛡️ **Security Dashboard**
- **Real-time Monitoring**: Security status at a glance
- **Automated Scanning**: Continuous security checks
- **Integrity Verification**: Content hash validation
- **Deployment Gates**: Multiple security checks before going live

## 🎯 User Interface Tour

### Dashboard
- **Posts Counter**: Total published posts
- **Security Status**: A+ security rating display
- **Last Deploy**: When your site was last updated
- **Quick Actions**: Fast access to common tasks

### Post Editor
- **Split View**: Markdown editor + live preview
- **Metadata Fields**: Title, slug, tags, publication date
- **Image Integration**: Paste or drag images directly
- **Format Toolbar**: Bold, italic, headers, links (coming soon)

### Media Library
- **Grid View**: Visual browsing of all images
- **Upload Zone**: Drag & drop multiple files
- **Auto-Optimization**: Automatic image compression
- **CDN Integration**: Direct upload to your CDN

### Theme Editor
- **Template Files**: Edit layout.html, post.html, etc.
- **Live Preview**: See changes without rebuilding
- **Component System**: Reusable headers, footers, navigation
- **Security Scanning**: Automatic JavaScript removal

### Security Center
- **Security Checklist**: All protections verified
- **Scan Results**: Real-time security analysis  
- **Audit Logs**: Track all admin actions
- **Compliance Status**: OWASP, NIST compliance tracking

## 📱 Mobile Experience

The admin interface is fully responsive:
- **Phone**: Stacked layout, touch-optimized
- **Tablet**: Sidebar collapses to drawer menu
- **Desktop**: Full three-column layout

## 🔧 Advanced Features

### Auto-Formatting
```bash
# Runs automatically on save/deploy
- Go code formatting
- Markdown standardization  
- JSON/YAML formatting
- Shell script linting
- Security pattern detection
```

### Deployment Pipeline
```
1. Content auto-formatting
2. Security regression guard
3. Site generation (sandboxed)
4. Link validation
5. Content integrity signing
6. CDN deployment
7. Git auto-commit (optional)
```

### Content Security
- **Input Sanitization**: All content automatically cleaned
- **XSS Prevention**: HTML sanitization on every save
- **Path Validation**: No directory traversal possible
- **File Type Checking**: Only safe file types allowed
- **Size Limits**: 10MB max per file

## ⚙️ Configuration

### Environment Variables
```bash
# Required for deployment
export ADMIN_PASSWORD="your-secure-password"
export CF_API_TOKEN="your-cloudflare-token"
export CF_ACCOUNT_ID="your-account-id"  
export CF_PAGES_PROJECT="your-project-name"

# Optional
export AUTO_COMMIT="true"     # Auto-commit changes
export AUTO_PUSH="true"       # Auto-push to git
export DEBUG_MODE="false"     # Enable debug logging
```

### Security Settings
```bash
# All security features are enabled by default and cannot be disabled
✅ Zero JavaScript enforcement
✅ Content Security Policy (strict)
✅ XSS protection
✅ Path traversal prevention
✅ File upload restrictions
✅ Session security
✅ HTTPS enforcement
✅ Input sanitization
```

## 🎨 Customizing Your Admin

### Themes
The admin interface supports custom themes. Edit `ui/admin.css` to:
- Change color schemes
- Modify layout spacing
- Add custom fonts
- Adjust mobile breakpoints

### Logo & Branding
Replace the logo in the header by editing `ui/admin.html`:
```html
<div class="logo">
    🔒 YourBlog
    <span class="security-badge">ULTRA SECURE</span>
</div>
```

## 🔍 Troubleshooting

### Common Issues

#### "Port 3000 already in use"
```bash
# Find what's using the port
lsof -i :3000

# Kill the process
kill -9 <PID>

# Or change the port in cmd/admin-server/main.go
```

#### "Admin interface not found"  
```bash
# Make sure ui/admin.html exists
ls ui/admin.html

# If missing, the file should be in the repository
```

#### "Deployment fails"
```bash
# Check environment variables
echo $CF_API_TOKEN
echo $CF_ACCOUNT_ID
echo $CF_PAGES_PROJECT

# Test Cloudflare connection
wrangler whoami
```

### Performance Tips

#### For Large Blogs (100+ posts)
- Enable pagination in post list
- Use image optimization
- Enable browser caching
- Consider CDN for admin assets

#### For Multiple Users
- Deploy multiple admin instances
- Use different ports (3000, 3001, 3002)
- Separate content directories
- Use Git branches for collaboration

## 🚀 Deployment Workflows

### Local Development
```bash
./start-admin.sh          # Start admin
# Edit content via web interface
# Preview changes locally
```

### Production Deployment
```bash
# Option 1: One-click deploy (from admin)
Click "🚀 Deploy" button in admin interface

# Option 2: Command line
bash scripts/deploy-secure.sh

# Option 3: Automated (via CI/CD)
# Commits to main branch auto-deploy
```

### Content Collaboration
```bash
# Multiple editors workflow
git checkout -b content/new-post
# Edit via admin interface  
git commit -am "Add new post"
git push origin content/new-post
# Create PR for review
```

## 🛡️ Security Best Practices

### Admin Access
- **Strong Passwords**: Use 20+ character passwords
- **HTTPS Only**: Always use HTTPS in production
- **IP Restrictions**: Restrict admin access to known IPs
- **VPN Access**: Connect via VPN for remote access
- **Session Timeout**: Regular session expiration

### Content Security
- **Review Mode**: Review all content before publishing
- **Version Control**: All changes tracked in Git
- **Backup Strategy**: Regular automated backups
- **Integrity Checks**: Verify content hasn't been tampered with

### Infrastructure Security
- **CDN-Only**: Never expose origin servers
- **DNS Security**: Use Cloudflare DNS with security features
- **SSL/TLS**: Always use HTTPS with HSTS
- **Monitoring**: Set up uptime and security monitoring

## 📊 Analytics & Monitoring

### Built-in Analytics
- **Page Views**: Basic traffic statistics
- **Security Events**: Failed login attempts, blocked requests
- **Performance**: Build times, deployment duration
- **Content**: Most popular posts, recent changes

### External Integrations
- **Google Analytics**: Privacy-focused analytics
- **Plausible**: GDPR-compliant analytics
- **Cloudflare Analytics**: Server-side analytics
- **Uptime Monitoring**: 24/7 availability checks

## 🆘 Getting Help

### Documentation
- 📖 [Security Audit Report](./SECURITY-AUDIT.md)
- 🏃 [Beginner Guide](./docs/BEGINNER-GUIDE.md)  
- 🔧 [Plugin Development](./docs/PLUGIN-GUIDE.md)
- 📝 [WordPress Migration](./docs/WORDPRESS_MIGRATION.md)

### Community
- 🐛 Issues: [GitHub Issues](https://github.com/techmad220/secureblog/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/techmad220/secureblog/discussions)
- 📧 Security: security@secureblog.dev

---

**Now you have WordPress-level ease with Fort Knox-level security!** 🎉

*Your blog is so secure, it would take nation-state actors to break it, but so easy to use, your grandma could publish posts.* 👵💻