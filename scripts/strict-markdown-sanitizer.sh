#!/bin/bash
# Strict Markdown/HTML Sanitization with Zero Raw HTML
# Implements fail-closed sanitization with comprehensive testing

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTENT_DIR="${1:-content}"
OUTPUT_DIR="${2:-dist}"

echo -e "${BLUE}🧹 STRICT MARKDOWN/HTML SANITIZATION${NC}"
echo "===================================="
echo "Content directory: $CONTENT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo

TOTAL_FILES=0
FAILED_FILES=0
SANITIZED_FILES=0

# Create sanitization report
REPORT_FILE="/tmp/sanitization-report-$$.json"
echo '{"files": [], "summary": {}}' > "$REPORT_FILE"

# Function to check for raw HTML in markdown
check_raw_html() {
    local file="$1"
    local violations=0
    
    echo "Checking for raw HTML in: $file"
    
    # Patterns that indicate raw HTML (not in code blocks)
    local html_patterns=(
        '<script[^>]*>'
        '<iframe[^>]*>'
        '<object[^>]*>'
        '<embed[^>]*>'
        '<form[^>]*>'
        '<input[^>]*>'
        '<button[^>]*>'
        '<audio[^>]*>'
        '<video[^>]*>'
        '<canvas[^>]*>'
        '<svg[^>]*>'
        '<math[^>]*>'
        '<template[^>]*>'
        'on[a-z]+='
        'javascript:'
        'vbscript:'
        'data:[^,]*javascript'
        'expression\('
        '@import'
        '-moz-binding'
        'behavior:'
    )
    
    # Check if file is in code block (simplistic check)
    local in_code_block=false
    local line_num=0
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Track code block state
        if [[ "$line" =~ ^\`\`\` ]]; then
            if [ "$in_code_block" = "true" ]; then
                in_code_block=false
            else
                in_code_block=true
            fi
            continue
        fi
        
        # Skip lines in code blocks
        if [ "$in_code_block" = "true" ]; then
            continue
        fi
        
        # Check for HTML patterns outside code blocks
        for pattern in "${html_patterns[@]}"; do
            if echo "$line" | grep -iE "$pattern" >/dev/null; then
                echo -e "${RED}  ✗ Line $line_num: Raw HTML detected: $pattern${NC}"
                echo "    Content: $(echo "$line" | sed 's/^[ \t]*//')"
                violations=$((violations + 1))
            fi
        done
        
    done < "$file"
    
    return $violations
}

# Function to sanitize markdown content
sanitize_markdown() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Sanitizing markdown: $input_file -> $output_file"
    
    # Create Go program for strict sanitization
    cat > /tmp/sanitizer.go << 'EOF'
package main

import (
    "bufio"
    "fmt"
    "os"
    "regexp"
    "strings"
)

func main() {
    if len(os.Args) != 3 {
        fmt.Fprintf(os.Stderr, "Usage: %s input output\n", os.Args[0])
        os.Exit(1)
    }
    
    inputFile := os.Args[1]
    outputFile := os.Args[2]
    
    // Dangerous patterns to completely remove
    dangerousPatterns := []*regexp.Regexp{
        regexp.MustCompile(`(?i)<script[^>]*>.*?</script>`),
        regexp.MustCompile(`(?i)<script[^>]*>`),
        regexp.MustCompile(`(?i)</script>`),
        regexp.MustCompile(`(?i)<iframe[^>]*>.*?</iframe>`),
        regexp.MustCompile(`(?i)<iframe[^>]*>`),
        regexp.MustCompile(`(?i)<object[^>]*>.*?</object>`),
        regexp.MustCompile(`(?i)<embed[^>]*>`),
        regexp.MustCompile(`(?i)<form[^>]*>.*?</form>`),
        regexp.MustCompile(`(?i)<input[^>]*>`),
        regexp.MustCompile(`(?i)<button[^>]*>.*?</button>`),
        regexp.MustCompile(`(?i)<audio[^>]*>.*?</audio>`),
        regexp.MustCompile(`(?i)<video[^>]*>.*?</video>`),
        regexp.MustCompile(`(?i)<canvas[^>]*>.*?</canvas>`),
        regexp.MustCompile(`(?i)<svg[^>]*>.*?</svg>`),
        regexp.MustCompile(`(?i)<math[^>]*>.*?</math>`),
        regexp.MustCompile(`(?i)<template[^>]*>.*?</template>`),
        regexp.MustCompile(`(?i)on[a-z]+\s*=\s*["\'][^"\']*["\']`),
        regexp.MustCompile(`(?i)on[a-z]+\s*=\s*[^"\'\s>]+`),
        regexp.MustCompile(`(?i)javascript:`),
        regexp.MustCompile(`(?i)vbscript:`),
        regexp.MustCompile(`(?i)data:[^,]*javascript`),
        regexp.MustCompile(`(?i)expression\s*\(`),
        regexp.MustCompile(`(?i)@import`),
        regexp.MustCompile(`(?i)-moz-binding`),
        regexp.MustCompile(`(?i)behavior\s*:`),
    }
    
    // Read input file
    file, err := os.Open(inputFile)
    if err != nil {
        fmt.Fprintf(os.Stderr, "Error opening input file: %v\n", err)
        os.Exit(1)
    }
    defer file.Close()
    
    var content strings.Builder
    scanner := bufio.NewScanner(file)
    inCodeBlock := false
    
    for scanner.Scan() {
        line := scanner.Text()
        
        // Track code block state (simplified)
        if strings.HasPrefix(strings.TrimSpace(line), "```") {
            inCodeBlock = !inCodeBlock
            content.WriteString(line + "\n")
            continue
        }
        
        // Don't sanitize content inside code blocks
        if inCodeBlock {
            content.WriteString(line + "\n")
            continue
        }
        
        // Apply sanitization patterns
        sanitizedLine := line
        for _, pattern := range dangerousPatterns {
            sanitizedLine = pattern.ReplaceAllString(sanitizedLine, "[REMOVED: DANGEROUS CONTENT]")
        }
        
        // Additional sanitization: remove any remaining HTML tags except safe ones
        safeTagPattern := regexp.MustCompile(`<(?!\/?(h[1-6]|p|br|hr|strong|em|b|i|u|ul|ol|li|a\s|img\s|blockquote|code|pre)\b)[^>]*>`)
        sanitizedLine = safeTagPattern.ReplaceAllString(sanitizedLine, "[REMOVED: HTML TAG]")
        
        content.WriteString(sanitizedLine + "\n")
    }
    
    if err := scanner.Err(); err != nil {
        fmt.Fprintf(os.Stderr, "Error reading file: %v\n", err)
        os.Exit(1)
    }
    
    // Write output file
    output, err := os.Create(outputFile)
    if err != nil {
        fmt.Fprintf(os.Stderr, "Error creating output file: %v\n", err)
        os.Exit(1)
    }
    defer output.Close()
    
    _, err = output.WriteString(content.String())
    if err != nil {
        fmt.Fprintf(os.Stderr, "Error writing output file: %v\n", err)
        os.Exit(1)
    }
}
EOF
    
    # Compile and run sanitizer
    if go build -o /tmp/sanitizer /tmp/sanitizer.go; then
        /tmp/sanitizer "$input_file" "$output_file"
        rm -f /tmp/sanitizer /tmp/sanitizer.go
    else
        echo -e "${RED}Failed to compile sanitizer${NC}"
        return 1
    fi
}

# Function to create golden tests for dangerous patterns
create_golden_tests() {
    local test_dir="/tmp/markdown-security-tests"
    mkdir -p "$test_dir"
    
    echo "Creating golden tests for dangerous patterns..."
    
    # Test 1: SVG onload attack
    cat > "$test_dir/test-svg-onload.md" << 'EOF'
# Test SVG onload attack

This should be sanitized:
<svg onload="alert('xss')">
  <circle r="10"/>
</svg>

This is safe:
```html
<svg onload="alert('safe in code block')">
```
EOF
    
    # Test 2: Data URL attack
    cat > "$test_dir/test-data-url.md" << 'EOF'
# Test Data URL attack

Dangerous data URL:
<img src="data:text/html,<script>alert('xss')</script>" alt="evil">

Safe data URL:
<img src="data:image/png;base64,iVBORw0KGgoAAAANS..." alt="safe">
EOF
    
    # Test 3: Nested iframe attack
    cat > "$test_dir/test-nested-iframe.md" << 'EOF'
# Test Nested iframe attack

This should be completely removed:
<iframe src="javascript:alert('xss')"></iframe>

<iframe>
  <script>alert('nested attack')</script>
</iframe>
EOF
    
    # Test 4: Event handler variations
    cat > "$test_dir/test-event-handlers.md" << 'EOF'
# Test Event handlers

All of these should be sanitized:
<div onclick="alert('click')">Click me</div>
<img src="image.jpg" onload="alert('load')" alt="test">
<p onmouseover="alert('mouse')">Hover me</p>
<a href="#" onfocus="alert('focus')">Focus me</a>
EOF
    
    # Test 5: CSS injection
    cat > "$test_dir/test-css-injection.md" << 'EOF'
# Test CSS injection

Dangerous CSS:
<div style="background: url(javascript:alert('css'))">CSS attack</div>
<div style="width: expression(alert('ie'))">IE expression</div>
<style>@import url(javascript:alert('import'))</style>
EOF
    
    # Run tests
    local test_failures=0
    for test_file in "$test_dir"/*.md; do
        test_name=$(basename "$test_file" .md)
        output_file="$test_dir/${test_name}-output.md"
        
        echo "Running test: $test_name"
        
        if sanitize_markdown "$test_file" "$output_file"; then
            # Check if dangerous content was removed
            if grep -iE "(javascript:|onload=|<script|<iframe)" "$output_file" >/dev/null; then
                echo -e "${RED}  ✗ Test failed: Dangerous content not removed${NC}"
                echo "  Remaining content:"
                grep -iE "(javascript:|onload=|<script|<iframe)" "$output_file" | head -3
                test_failures=$((test_failures + 1))
            else
                echo -e "${GREEN}  ✓ Test passed: Dangerous content removed${NC}"
            fi
        else
            echo -e "${RED}  ✗ Test failed: Sanitization error${NC}"
            test_failures=$((test_failures + 1))
        fi
    done
    
    rm -rf "$test_dir"
    return $test_failures
}

# Main sanitization process
echo -e "${BLUE}1. Running Golden Tests...${NC}"
if create_golden_tests; then
    echo -e "${GREEN}   ✓ All golden tests passed${NC}"
else
    echo -e "${RED}   ✗ Golden tests failed - aborting sanitization${NC}"
    exit 1
fi

echo -e "${BLUE}2. Checking for Raw HTML in Markdown Files...${NC}"

# Process all markdown files
find "$CONTENT_DIR" -name "*.md" -type f | while read file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    
    # Check for raw HTML first
    if check_raw_html "$file"; then
        echo -e "${RED}Raw HTML found in: $file${NC}"
        FAILED_FILES=$((FAILED_FILES + 1))
        
        # Add to report
        jq --arg file "$file" --arg status "failed" --arg reason "raw_html_detected" \
           '.files += [{"file": $file, "status": $status, "reason": $reason}]' \
           "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
    else
        echo -e "${GREEN}   ✓ No raw HTML found in: $file${NC}"
        
        # Sanitize the file
        output_file="$OUTPUT_DIR/$(basename "$file")"
        mkdir -p "$(dirname "$output_file")"
        
        if sanitize_markdown "$file" "$output_file"; then
            SANITIZED_FILES=$((SANITIZED_FILES + 1))
            echo -e "${GREEN}   ✓ Sanitized: $output_file${NC}"
            
            jq --arg file "$file" --arg output "$output_file" --arg status "sanitized" \
               '.files += [{"file": $file, "output": $output, "status": $status}]' \
               "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
        else
            echo -e "${RED}   ✗ Failed to sanitize: $file${NC}"
            FAILED_FILES=$((FAILED_FILES + 1))
            
            jq --arg file "$file" --arg status "failed" --arg reason "sanitization_error" \
               '.files += [{"file": $file, "status": $status, "reason": $reason}]' \
               "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
        fi
    fi
done

# Update summary in report
jq --arg total "$TOTAL_FILES" --arg sanitized "$SANITIZED_FILES" --arg failed "$FAILED_FILES" \
   '.summary = {"total_files": ($total|tonumber), "sanitized_files": ($sanitized|tonumber), "failed_files": ($failed|tonumber)}' \
   "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"

echo
echo -e "${BLUE}SANITIZATION REPORT${NC}"
echo "==================="
echo "Total files processed: $TOTAL_FILES"
echo -e "Successfully sanitized: ${GREEN}$SANITIZED_FILES${NC}"
echo -e "Failed/contained raw HTML: ${RED}$FAILED_FILES${NC}"

if [ -f "$REPORT_FILE" ]; then
    echo
    echo "Detailed report:"
    cat "$REPORT_FILE" | jq '.'
    
    # Copy report to output directory
    cp "$REPORT_FILE" "$OUTPUT_DIR/sanitization-report.json"
fi

# Cleanup
rm -f "$REPORT_FILE" "$REPORT_FILE.tmp"

if [ $FAILED_FILES -gt 0 ]; then
    echo
    echo -e "${RED}❌ SANITIZATION FAILED${NC}"
    echo "Some files contain raw HTML or failed to sanitize."
    echo "Build MUST fail to prevent publication of dangerous content."
    echo
    echo "🔧 To fix:"
    echo "1. Remove all raw HTML from markdown files"
    echo "2. Use only safe markdown syntax"
    echo "3. Put HTML examples in code blocks (```html)"
    exit 1
else
    echo
    echo -e "${GREEN}✅ ALL MARKDOWN FILES SUCCESSFULLY SANITIZED${NC}"
    echo "No raw HTML detected, all content safe for publication."
    exit 0
fi