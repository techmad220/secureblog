# SecureBlog Beginner's Guide

Welcome! This guide will help you set up your ultra-secure blog in 15 minutes, even if you're new to command-line tools.

## Prerequisites

You'll need:
- A computer (Windows, Mac, or Linux)
- Basic text editing skills
- 15 minutes

## Step 1: Install Go (5 minutes)

### Windows
1. Download Go from https://go.dev/dl/
2. Run the installer (click Next, Next, Finish)
3. Open Command Prompt and type: `go version`

### Mac
```bash
# Using Homebrew (if installed)
brew install go

# Or download from https://go.dev/dl/
```

### Linux
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install golang-go

# Or download from https://go.dev/dl/
```

## Step 2: Get SecureBlog (2 minutes)

### Option A: Download ZIP (Easiest)
1. Go to https://github.com/techmad220/secureblog
2. Click green "Code" button → "Download ZIP"
3. Extract to your Desktop

### Option B: Use Git
```bash
git clone https://github.com/techmad220/secureblog.git
cd secureblog
```

## Step 3: Write Your First Post (3 minutes)

1. Navigate to `content/posts/` folder
2. Create a new file called `my-first-post.md`
3. Add this content:

```markdown
# My First Secure Blog Post

Welcome to my blog! This is my first post.

## Why I Chose SecureBlog

- No JavaScript = No hacking
- Super fast loading
- Complete privacy for my readers
- I control everything

This is going to be great!
```

4. Save the file

## Step 4: Build Your Blog (2 minutes)

### Windows (Command Prompt)
```cmd
cd Desktop\secureblog
go run cmd/main_v2.go
```

### Mac/Linux (Terminal)
```bash
cd ~/Desktop/secureblog
go run cmd/main_v2.go
```

Your blog is now in the `build/` folder!

## Step 5: Preview Locally (1 minute)

### Python (usually pre-installed)
```bash
cd build
python -m http.server 8000
# Or for Python 2: python -m SimpleHTTPServer 8000
```

Open your browser to: http://localhost:8000

### No Python? Use Node.js
```bash
npx serve build
```

## Step 6: Deploy to the Internet (2 minutes)

### Easiest: Netlify Drop
1. Go to https://app.netlify.com/drop
2. Drag your `build` folder onto the page
3. Done! Your blog is live!

### Free & Secure: Cloudflare Pages
1. Go to https://pages.cloudflare.com
2. Click "Create a project" → "Direct Upload"
3. Upload your `build` folder
4. Done! You get a free `*.pages.dev` URL

## Common Tasks

### Adding a New Post
1. Create new `.md` file in `content/posts/`
2. Run `go run cmd/main_v2.go`
3. Upload new `build/` folder

### Changing the Look
Edit `templates/index.html` and `templates/post.html`
- Change colors in `<style>` section
- Modify layout in `<body>` section
- Keep it simple - no JavaScript!

### Adding Your Domain
1. Buy domain from Namecheap/Google Domains
2. In Cloudflare Pages → Custom Domains
3. Add your domain
4. Follow DNS instructions

## Troubleshooting

### "go: command not found"
Go isn't installed. Return to Step 1.

### "no such file or directory"
You're in the wrong folder. Use `cd` to navigate to secureblog folder.

### Build errors
```bash
# Fix missing dependencies
go mod download

# Clean and rebuild
rm -rf build
go run cmd/main_v2.go
```

### Page looks broken
Check you're viewing through a web server (Step 5), not opening HTML files directly.

## Security Check

After deploying, verify your security:
1. Go to https://securityheaders.com
2. Enter your blog URL
3. You should get an A+ rating!

## Next Steps

### Learn Markdown
- Headers: `# Big` `## Medium` `### Small`
- Bold: `**bold text**`
- Links: `[text](https://url.com)`
- Images: `![alt text](image.jpg)`

### Customize Your Blog
- Edit `config.yaml` for site title/description
- Modify templates for custom design
- Add more posts!

### Join the Community
- Star the repo on GitHub
- Report issues if you find them
- Share your secure blog with others!

## Quick Command Reference

```bash
# Build blog
go run cmd/main_v2.go

# Test locally
cd build && python -m http.server 8000

# Security check
make audit

# Clean rebuild
rm -rf build && go run cmd/main_v2.go
```

## FAQ

**Q: Can I add comments?**
A: Use GitHub Discussions or embed a privacy-respecting service like Utterances (still no JS on your site).

**Q: Can I add analytics?**
A: Yes! Use Cloudflare's edge analytics (no JavaScript needed).

**Q: How do I backup?**
A: Your `content/posts/` folder is all you need. Back it up anywhere.

**Q: Can I use images?**
A: Yes! Put them in `static/images/` and reference with `![](images/photo.jpg)`

**Q: Is this really secure?**
A: Yes! No JavaScript = no XSS attacks. No server = no server hacks. No database = no SQL injection.

## You're Done! 🎉

Congratulations! You now have the most secure blog on the internet. 

Remember:
- **Never add JavaScript** (it breaks the security model)
- **Write in Markdown** (it's simple and safe)
- **Build and deploy** (two commands, that's it!)

Happy blogging! 🔒