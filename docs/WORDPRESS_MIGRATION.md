# WordPress to SecureBlog Migration Guide

## Why Migrate from WordPress?

### WordPress Security Issues:
- **43% of all hacked websites** are WordPress sites
- **96% of hacked WordPress sites** were out of date
- **Plugin vulnerabilities** account for 52% of breaches
- **Constant patches** - Average 50+ security updates per year
- **Database attacks** - SQL injection remains common
- **PHP exploits** - Remote code execution risks

### SecureBlog Advantages:
- **Maximum Security** - No server, database, or PHP to exploit
- **Zero maintenance** - No security updates needed
- **100% uptime** - CDN-based, globally distributed
- **Blazing fast** - Static HTML vs dynamic PHP
- **Free hosting** - GitHub Pages or $5/mo Cloudflare

## Migration Process

### Step 1: Export WordPress Content

```bash
# From WordPress Admin
Tools → Export → All Content → Download Export File

# Or use WP-CLI
wp export --dir=/backup/
```

### Step 2: Convert to Markdown

```bash
# Install wordpress-to-markdown converter
npm install -g wordpress-export-to-markdown

# Convert WordPress XML to Markdown
wordpress-export-to-markdown --input wordpress.xml --output content/posts/
```

### Step 3: Migrate Images

```bash
# Download all WordPress media
wget -r -l inf -np -nH --cut-dirs=3 \
  -R index.html -P static/images/ \
  https://yoursite.com/wp-content/uploads/

# Add to SecureBlog
for img in wordpress-images/*; do
  ./blog image "$img"
done
```

### Step 4: Set Up Redirects

Create `_redirects` file for old WordPress URLs:

```
# Redirect WordPress URLs to new structure
/2024/01/old-post-slug /posts/old-post-slug 301
/category/* /tags/:splat 301
/wp-admin / 301
/wp-login.php / 301
```

### Step 5: Deploy SecureBlog

```bash
# Initialize SecureBlog
git clone https://github.com/techmad220/secureblog
cd secureblog

# Copy converted content
cp -r /path/to/converted/posts/* content/posts/

# Build and deploy
./blog build
./blog deploy
```

## Feature Comparison

| Feature | WordPress | SecureBlog Equivalent |
|---------|-----------|----------------------|
| **Writing Posts** | Gutenberg Editor | Markdown + `./blog new` |
| **Media Library** | WP Media Manager | `static/images/` + `./blog image` |
| **Themes** | PHP Templates | Go Templates |
| **Plugins** | 60,000+ plugins | Build-time plugins only |
| **Comments** | Native/Disqus | Use GitHub Discussions |
| **SEO** | Yoast/RankMath | Built-in static SEO |
| **Analytics** | Google Analytics | Privacy-preserving edge analytics |
| **Search** | PHP/MySQL search | Static search (lunr.js alternative) |
| **Users** | WP user system | GitHub contributors |
| **Backups** | Plugins/manual | Git history (infinite) |

## Common WordPress Features → SecureBlog Solutions

### Comments
**WordPress**: Native comments, Disqus, etc.
**SecureBlog**: 
- Option 1: GitHub Discussions (no JS needed)
- Option 2: Static form → Email notifications
- Option 3: Remove comments (most secure)

### Contact Forms
**WordPress**: Contact Form 7, WPForms, etc.
**SecureBlog**:
```html
<!-- Use Cloudflare Workers for form handling -->
<form action="/api/contact" method="POST">
  <input type="email" name="email" required>
  <textarea name="message" required></textarea>
  <button type="submit">Send</button>
</form>
```

### E-commerce
**WordPress**: WooCommerce
**SecureBlog**: 
- Static product pages
- Stripe/PayPal buttons (no JS)
- Or use separate e-commerce platform

### Related Posts
**WordPress**: Plugins
**SecureBlog**: Build-time generation
```go
// In your build process
func generateRelatedPosts(post Post) []Post {
    // Find posts with similar tags
    return findSimilarPosts(post.Tags)
}
```

### Custom Post Types
**WordPress**: CPT plugins
**SecureBlog**: Different template directories
```
content/
├── posts/       # Blog posts
├── products/    # Product pages
└── docs/        # Documentation
```

## Performance Comparison

### WordPress (typical):
- **Time to First Byte**: 800-2000ms
- **Page Load**: 3-8 seconds
- **Requests**: 50-150
- **Page Size**: 2-5MB

### SecureBlog:
- **Time to First Byte**: 50-200ms
- **Page Load**: 0.5-1.5 seconds  
- **Requests**: 5-15
- **Page Size**: 50-200KB

## Security Comparison

### WordPress Attack Vectors:
```
[Internet] → [WordPress]
    ↓
- XML-RPC attacks
- wp-login.php brute force
- Plugin vulnerabilities
- Theme exploits
- SQL injection
- PHP code execution
- File upload exploits
- Admin panel attacks
```

### SecureBlog Attack Surface:
```
[Internet] → [CDN] → [Static HTML]
    ↓
- None (no server to attack)
- No database
- No admin panel
- No PHP/runtime
- No file uploads
- No user accounts
```

## Cost Comparison

### WordPress (Annual):
- Hosting: $120-600
- Security plugins: $100-300
- Backup service: $50-150
- CDN: $100-500
- SSL: $50-100
- **Total: $420-1,650/year**

### SecureBlog (Annual):
- GitHub Pages: $0
- Or Cloudflare: $60
- **Total: $0-60/year**

## Migration Checklist

- [ ] Export WordPress content
- [ ] Convert posts to Markdown
- [ ] Migrate images
- [ ] Set up redirects for old URLs
- [ ] Configure analytics
- [ ] Test all internal links
- [ ] Verify RSS feed
- [ ] Update DNS records
- [ ] Monitor 404s after launch

## FAQ

**Q: Can I keep my WordPress theme?**
A: You'll need to convert it to Go templates, but the HTML/CSS can be reused.

**Q: What about my plugins?**
A: Most plugin functionality needs to be replaced with build-time alternatives or removed.

**Q: Can users still comment?**
A: Yes, through GitHub Discussions or static forms, but not with traditional comment systems.

**Q: Will my SEO suffer?**
A: No, static sites often rank better due to speed. Set up proper redirects to maintain rankings.

**Q: Can I go back to WordPress?**
A: Yes, your content is in Markdown/Git and can be imported back if needed.

## Getting Help

- GitHub Issues: https://github.com/techmad220/secureblog/issues
- Documentation: https://github.com/techmad220/secureblog/docs
- Security Questions: See SECURITY.md

## Summary

Migrating from WordPress to SecureBlog means:
- **Trading convenience for security**
- **Trading features for performance**
- **Trading complexity for simplicity**
- **Trading costs for savings**

For security-conscious blogs, the trade-offs are worth it.