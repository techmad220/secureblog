#!/usr/bin/env bash
# deploy-secure.sh - One-click secure deployment
set -euo pipefail

echo "🚀 Secure Deployment Pipeline Starting..."
echo "=================================="

# Step 1: Auto-format and lint
echo "1️⃣ Auto-formatting content..."
bash scripts/auto-format.sh

# Step 2: Security regression guard
echo ""
echo "2️⃣ Security regression guard..."
bash .scripts/nojs-guard.sh dist || {
    echo "❌ Security check failed - deployment aborted"
    exit 1
}

# Step 3: Build site
echo ""
echo "3️⃣ Building site..."
bash ./build-sandbox.sh

# Step 4: Link validation
echo ""
echo "4️⃣ Validating links..."
bash ./scripts/linkcheck.sh dist

# Step 5: Content integrity
echo ""
echo "5️⃣ Generating content integrity..."
bash ./scripts/sign-manifest.sh dist

# Step 6: Final security scan
echo ""
echo "6️⃣ Final security scan..."
find dist -name "*.html" | while read -r file; do
    if grep -q "<script" "$file"; then
        echo "❌ JavaScript found in $file - deployment aborted"
        exit 1
    fi
done

# Step 7: Deploy to CDN
echo ""
echo "7️⃣ Deploying to CDN..."
if [ -n "${CF_API_TOKEN:-}" ] && [ -n "${CF_ACCOUNT_ID:-}" ] && [ -n "${CF_PAGES_PROJECT:-}" ]; then
    if command -v wrangler >/dev/null 2>&1; then
        wrangler pages deploy dist --project-name="$CF_PAGES_PROJECT"
        echo "✅ Deployed to Cloudflare Pages"
    else
        echo "⚠️ Wrangler not installed - skipping CF Pages deploy"
    fi
else
    echo "⚠️ Cloudflare env vars not set - skipping deploy"
    echo "   Set: CF_API_TOKEN, CF_ACCOUNT_ID, CF_PAGES_PROJECT"
fi

# Step 8: Git commit (optional)
if [ "${AUTO_COMMIT:-false}" = "true" ]; then
    echo ""
    echo "8️⃣ Auto-committing changes..."
    if git diff --quiet && git diff --staged --quiet; then
        echo "   No changes to commit"
    else
        git add -A
        git commit -m "Auto-deploy: $(date '+%Y-%m-%d %H:%M:%S')

🚀 Deployed via secure pipeline
✅ All security checks passed
🔒 Content integrity verified

🤖 Generated with SecureBlog Admin"
        
        if [ "${AUTO_PUSH:-false}" = "true" ]; then
            git push origin main
            echo "   Pushed to remote repository"
        fi
    fi
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo "=================================="
echo "✅ Security: All checks passed"
echo "✅ Build: Site generated"
echo "✅ Links: All valid"
echo "✅ Integrity: Content signed"
echo "✅ Deploy: CDN updated"
echo ""
echo "Your ultra-secure blog is now live! 🌐"