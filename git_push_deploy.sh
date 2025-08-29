#!/bin/bash

# Quick GitHub Push Script for SecureBlog

echo "🚀 Pushing SecureBlog to GitHub"
echo "================================"
echo ""

# Ensure we're in the right directory
cd /data/data/com.termux/files/home/secureblog

# Check git status
echo "📊 Repository Status:"
git status --short
echo ""

# Get GitHub username
echo "Enter your GitHub username:"
read GITHUB_USER

echo ""
echo "📝 Instructions:"
echo "1. First, create a new repo on GitHub:"
echo "   https://github.com/new"
echo "   - Name: secureblog"
echo "   - Set to PUBLIC"
echo "   - DON'T initialize with README"
echo ""
read -p "Press Enter when ready..."

# Add remote
echo ""
echo "Adding GitHub remote..."
git remote remove origin 2>/dev/null
git remote add origin "https://github.com/${GITHUB_USER}/secureblog.git"

# Create final commit with everything
git add -A
git commit -m "🚀 SecureBlog - Ultra-secure static blog generator

Features:
- Zero JavaScript (maximum security)
- Plugin-based architecture
- Privacy-first analytics (Cloudflare edge)
- Automated transparency dashboard
- Content Security Policy enforcement
- SHA256 integrity hashing
- Static HTML generation

Ready for production deployment!" 2>/dev/null || echo "Already committed"

# Push to GitHub
echo ""
echo "Pushing to GitHub..."
echo "You'll be prompted for your GitHub username and password/token"
echo ""
echo "NOTE: GitHub requires a Personal Access Token (not password)"
echo "Get one here: https://github.com/settings/tokens/new"
echo "Select 'repo' scope"
echo ""

git branch -M main
git push -u origin main

echo ""
echo "✅ Success! Your repo is now at:"
echo "   https://github.com/${GITHUB_USER}/secureblog"
echo ""
echo "🖥️ To clone on your PC:"
echo "   git clone https://github.com/${GITHUB_USER}/secureblog.git"
echo "   cd secureblog"
echo "   ./launch.sh"
echo ""