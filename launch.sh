#!/bin/bash

# SecureBlog Production Launch Script
# This will guide you through deployment

set -e

echo "🚀 SecureBlog Production Deployment"
echo "===================================="
echo ""

# Check if git is initialized
if [ ! -d ".git" ]; then
    echo "❌ Not a git repository. Initializing..."
    git init
    git add -A
    git commit -m "Initial commit"
fi

echo "📋 Current Status:"
echo "- Git initialized ✓"
echo "- $(git rev-list --count HEAD) commits"
echo "- $(find content/posts -name "*.md" | wc -l) posts ready"
echo ""

echo "🔧 Step 1: GitHub Setup"
echo "-----------------------"
echo "1. Go to: https://github.com/new"
echo "2. Create a new repository named: secureblog"
echo "3. Make it PUBLIC (required for free Cloudflare Pages)"
echo "4. DON'T initialize with README (we have one)"
echo ""
read -p "Press Enter when GitHub repo is created..."

echo ""
echo "📤 Step 2: Push to GitHub"
echo "-------------------------"
echo "Enter your GitHub username:"
read GITHUB_USER

# Add remote
git remote add origin "https://github.com/${GITHUB_USER}/secureblog.git" 2>/dev/null || \
git remote set-url origin "https://github.com/${GITHUB_USER}/secureblog.git"

echo ""
echo "Pushing to GitHub..."
git branch -M main
git push -u origin main || {
    echo ""
    echo "⚠️  If push failed, you may need to:"
    echo "1. Create a Personal Access Token:"
    echo "   https://github.com/settings/tokens/new"
    echo "2. Use token as password when prompted"
    echo ""
    echo "Trying again..."
    git push -u origin main
}

echo "✅ Code pushed to GitHub!"
echo ""

echo "🌐 Step 3: Cloudflare Pages Setup"
echo "----------------------------------"
echo "1. Go to: https://pages.cloudflare.com"
echo "2. Click 'Create a project'"
echo "3. Click 'Connect to Git'"
echo "4. Authorize Cloudflare to access GitHub"
echo "5. Select: ${GITHUB_USER}/secureblog"
echo ""
echo "Build settings to use:"
echo "  Build command: go run cmd/main_v2.go -content=content -output=build"
echo "  Build output directory: build"
echo "  Root directory: /"
echo "  Go version: 1.21"
echo ""
read -p "Press Enter when Cloudflare Pages is connected..."

echo ""
echo "🔑 Step 4: Add Environment Variables (Optional)"
echo "------------------------------------------------"
echo "In Cloudflare Pages > Settings > Environment Variables:"
echo ""
echo "For analytics (optional):"
echo "  CF_API_TOKEN = your-cloudflare-api-token"
echo "  CF_ZONE_ID = your-cloudflare-zone-id"
echo ""
echo "To get these:"
echo "1. API Token: https://dash.cloudflare.com/profile/api-tokens"
echo "   - Create token with 'Zone:Read' and 'Analytics:Read'"
echo "2. Zone ID: Your domain in Cloudflare > Overview > Zone ID"
echo ""
read -p "Press Enter to continue..."

echo ""
echo "🎯 Step 5: Custom Domain (Optional)"
echo "------------------------------------"
echo "In Cloudflare Pages > Custom domains:"
echo "1. Click 'Set up a custom domain'"
echo "2. Enter your domain (e.g., blog.yourdomain.com)"
echo "3. Cloudflare will auto-configure DNS"
echo ""
echo "Your blog will be available at:"
echo "  https://${GITHUB_USER}-secureblog.pages.dev"
echo "  https://your-custom-domain.com (if configured)"
echo ""

echo "✨ Step 6: Trigger First Build"
echo "-------------------------------"
echo "The first build should start automatically."
echo "You can watch it at:"
echo "  https://pages.cloudflare.com"
echo ""

echo "📊 Step 7: Verify Deployment"
echo "----------------------------"
echo "Once built, check these URLs:"
echo "  https://${GITHUB_USER}-secureblog.pages.dev"
echo "  https://${GITHUB_USER}-secureblog.pages.dev/stats.html"
echo "  https://${GITHUB_USER}-secureblog.pages.dev/feed.xml"
echo ""

echo "🎉 Launch Complete!"
echo "==================="
echo ""
echo "Your ultra-secure blog is now live!"
echo ""
echo "Next steps:"
echo "1. Write more posts in content/posts/"
echo "2. Customize templates/"
echo "3. Share your first post on HackerNews/Reddit"
echo "4. Monitor analytics at /stats.html"
echo ""
echo "Security verification tools:"
echo "- https://securityheaders.com"
echo "- https://observatory.mozilla.org"
echo ""
echo "Happy blogging! 🔒"