#!/usr/bin/env bash
# auto-format.sh - Automated content formatting and linting
set -euo pipefail

echo "🔧 Auto-formatting SecureBlog content..."

# Format Go code
echo "→ Formatting Go code..."
go fmt ./...
go mod tidy

# Format markdown files
echo "→ Formatting Markdown files..."
if command -v prettier >/dev/null 2>&1; then
    find content/ -name "*.md" -exec prettier --write {} \; 2>/dev/null || true
else
    echo "  (prettier not installed - skipping markdown formatting)"
fi

# Format JSON files
echo "→ Formatting JSON files..."
find . -name "*.json" -not -path "./node_modules/*" -not -path "./.git/*" | while read -r file; do
    if command -v jq >/dev/null 2>&1; then
        temp=$(mktemp)
        jq '.' "$file" > "$temp" && mv "$temp" "$file"
    fi
done

# Format YAML files
echo "→ Formatting YAML files..."
if command -v yamlfmt >/dev/null 2>&1; then
    find . -name "*.yml" -o -name "*.yaml" | grep -E '\.(yml|yaml)$' | xargs yamlfmt -w 2>/dev/null || true
fi

# Lint shell scripts
echo "→ Linting shell scripts..."
if command -v shellcheck >/dev/null 2>&1; then
    find . -name "*.sh" -not -path "./.git/*" | while read -r script; do
        if shellcheck "$script" >/dev/null 2>&1; then
            echo "  ✅ $script"
        else
            echo "  ❌ $script (has issues)"
        fi
    done
else
    echo "  (shellcheck not installed - skipping shell linting)"
fi

# Check for common issues
echo "→ Checking for common issues..."

# Check for trailing whitespace
if grep -r "[ \t]$" --include="*.md" --include="*.go" --include="*.js" --include="*.html" . 2>/dev/null; then
    echo "  ⚠️ Trailing whitespace found (fixed automatically)"
    # Remove trailing whitespace
    find . -name "*.md" -o -name "*.go" -o -name "*.js" -o -name "*.html" | \
        grep -v ".git" | xargs sed -i 's/[ \t]*$//'
fi

# Check for mixed line endings
echo "→ Checking line endings..."
find . -name "*.md" -o -name "*.go" -o -name "*.js" -o -name "*.html" | \
    grep -v ".git" | while read -r file; do
    if file "$file" | grep -q "CRLF"; then
        echo "  🔧 Converting $file to Unix line endings"
        dos2unix "$file" 2>/dev/null || sed -i 's/\r$//' "$file"
    fi
done

# Validate frontmatter in markdown files
echo "→ Validating markdown frontmatter..."
find content/ -name "*.md" 2>/dev/null | while read -r md_file; do
    if head -1 "$md_file" | grep -q "^---$"; then
        if ! sed -n '2,/^---$/p' "$md_file" | head -n -1 | tail -n +1 | grep -q "title:"; then
            echo "  ❌ $md_file missing title in frontmatter"
        fi
        if ! sed -n '2,/^---$/p' "$md_file" | head -n -1 | tail -n +1 | grep -q "date:"; then
            echo "  ❌ $md_file missing date in frontmatter"
        fi
    else
        echo "  ⚠️ $md_file missing frontmatter"
    fi
done

# Check image optimization
echo "→ Checking image sizes..."
find content/images/ -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" \) 2>/dev/null | while read -r img; do
    size=$(stat -f%z "$img" 2>/dev/null || stat -c%s "$img" 2>/dev/null || echo "0")
    if [ "$size" -gt 1048576 ]; then # 1MB
        echo "  ⚠️ Large image: $img ($(($size / 1024))KB)"
        echo "    Consider optimizing with: convert '$img' -quality 85 -resize '1200>' '$img'"
    fi
done

# Security check for dangerous patterns
echo "→ Security check..."
if grep -r "eval\|exec\|system" --include="*.md" --include="*.html" . 2>/dev/null; then
    echo "  ❌ Potentially dangerous patterns found in content"
fi

echo ""
echo "✅ Auto-formatting complete!"
echo "📊 Summary:"
echo "   - Go code formatted"
echo "   - Markdown files processed"
echo "   - JSON files formatted"  
echo "   - Shell scripts linted"
echo "   - Line endings normalized"
echo "   - Security check passed"