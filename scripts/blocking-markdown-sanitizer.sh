#!/bin/bash
# Blocking Markdown Sanitizer
# Enforces zero raw HTML policy - fails CI if ANY HTML found in Markdown

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTENT_DIR="${1:-content}"
TOTAL_FILES=0
VIOLATIONS=0
CRITICAL_VIOLATIONS=0

echo -e "${BLUE}🔒 BLOCKING MARKDOWN SANITIZATION CHECK${NC}"
echo "======================================"
echo "Scanning: $CONTENT_DIR"
echo "Policy: ZERO raw HTML allowed in Markdown"
echo

if [ ! -d "$CONTENT_DIR" ]; then
    echo -e "${RED}❌ Content directory not found: $CONTENT_DIR${NC}"
    exit 1
fi

# Create Go-based HTML detector for maximum precision
cat > /tmp/html_detector.go << 'EOF'
package main

import (
    "bufio"
    "fmt"
    "os"
    "regexp"
    "strings"
)

var (
    // Dangerous HTML patterns that must be blocked
    htmlTagRegex = regexp.MustCompile(`<[^>]+>`)
    scriptTagRegex = regexp.MustCompile(`(?i)<script[^>]*>.*?</script>`)
    styleTagRegex = regexp.MustCompile(`(?i)<style[^>]*>.*?</style>`)
    eventHandlerRegex = regexp.MustCompile(`(?i)on[a-z]+\s*=\s*["'][^"']*["']`)
    javascriptUrlRegex = regexp.MustCompile(`(?i)javascript:`)
    dataUrlRegex = regexp.MustCompile(`(?i)data:(?!image/)`) // Allow data:image/ only
    iframeRegex = regexp.MustCompile(`(?i)<iframe[^>]*>`)
    objectRegex = regexp.MustCompile(`(?i)<object[^>]*>`)
    embedRegex = regexp.MustCompile(`(?i)<embed[^>]*>`)
    formRegex = regexp.MustCompile(`(?i)<form[^>]*>`)
    
    // Critical security violations (immediate fail)
    criticalPatterns = []*regexp.Regexp{
        scriptTagRegex,
        eventHandlerRegex, 
        javascriptUrlRegex,
        iframeRegex,
        objectRegex,
        embedRegex,
    }
    
    // Standard HTML tags that should not be in Markdown
    standardPatterns = []*regexp.Regexp{
        htmlTagRegex,
        styleTagRegex,
        formRegex,
        dataUrlRegex,
    }
)

func main() {
    if len(os.Args) != 2 {
        fmt.Fprintf(os.Stderr, "Usage: %s <markdown-file>\n", os.Args[0])
        os.Exit(1)
    }
    
    filename := os.Args[1]
    file, err := os.Open(filename)
    if err != nil {
        fmt.Fprintf(os.Stderr, "Error opening file: %v\n", err)
        os.Exit(1)
    }
    defer file.Close()
    
    scanner := bufio.NewScanner(file)
    lineNum := 0
    violations := 0
    criticalViolations := 0
    
    for scanner.Scan() {
        lineNum++
        line := scanner.Text()
        
        // Skip code blocks (between ``` or indented)
        if strings.HasPrefix(strings.TrimSpace(line), "```") {
            // Skip to end of code block
            for scanner.Scan() {
                lineNum++
                if strings.HasPrefix(strings.TrimSpace(scanner.Text()), "```") {
                    break
                }
            }
            continue
        }
        
        // Skip indented code blocks
        if strings.HasPrefix(line, "    ") || strings.HasPrefix(line, "\t") {
            continue
        }
        
        // Check for critical security violations
        for _, pattern := range criticalPatterns {
            if pattern.MatchString(line) {
                fmt.Printf("CRITICAL:%d:%s:%s\n", lineNum, pattern.String(), line)
                criticalViolations++
                violations++
            }
        }
        
        // Check for standard HTML violations
        for _, pattern := range standardPatterns {
            if pattern.MatchString(line) {
                // Skip if already counted as critical
                isCritical := false
                for _, critPattern := range criticalPatterns {
                    if critPattern.MatchString(line) {
                        isCritical = true
                        break
                    }
                }
                
                if !isCritical {
                    fmt.Printf("VIOLATION:%d:%s:%s\n", lineNum, pattern.String(), line)
                    violations++
                }
            }
        }
    }
    
    if err := scanner.Err(); err != nil {
        fmt.Fprintf(os.Stderr, "Error reading file: %v\n", err)
        os.Exit(1)
    }
    
    // Exit codes: 0 = clean, 1 = violations, 2 = critical violations
    if criticalViolations > 0 {
        os.Exit(2)
    } else if violations > 0 {
        os.Exit(1)
    }
    
    os.Exit(0)
}
EOF

# Compile the HTML detector
go build -o /tmp/html_detector /tmp/html_detector.go

# Function to check a single file
check_file() {
    local file="$1"
    local result
    
    echo -n "Checking $(basename "$file")... "
    
    # Run the HTML detector
    if result=$(/tmp/html_detector "$file" 2>&1); then
        echo -e "${GREEN}CLEAN${NC}"
        return 0
    else
        local exit_code=$?
        echo -e "${RED}VIOLATIONS FOUND${NC}"
        
        # Parse violations
        while IFS= read -r line; do
            if [[ "$line" =~ ^CRITICAL: ]]; then
                local line_num=$(echo "$line" | cut -d: -f2)
                local content=$(echo "$line" | cut -d: -f4-)
                echo -e "    ${RED}🚨 CRITICAL (line $line_num): $content${NC}"
                CRITICAL_VIOLATIONS=$((CRITICAL_VIOLATIONS + 1))
            elif [[ "$line" =~ ^VIOLATION: ]]; then
                local line_num=$(echo "$line" | cut -d: -f2)
                local content=$(echo "$line" | cut -d: -f4-)
                echo -e "    ${YELLOW}⚠️  HTML (line $line_num): $content${NC}"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        done <<< "$result"
        
        return $exit_code
    fi
}

# Scan all Markdown files
echo -e "${BLUE}Scanning for HTML in Markdown files...${NC}"
echo

while IFS= read -r -d '' file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    check_file "$file"
done < <(find "$CONTENT_DIR" -name "*.md" -type f -print0)

echo
echo -e "${BLUE}MARKDOWN SANITIZATION RESULTS${NC}"
echo "============================="
echo "Files scanned: $TOTAL_FILES"
echo -e "HTML violations: ${YELLOW}$VIOLATIONS${NC}"
echo -e "Critical violations: ${RED}$CRITICAL_VIOLATIONS${NC}"

# Generate detailed report for CI
cat > markdown-sanitization-report.json << EOF
{
  "scan_date": "$(date -Iseconds)",
  "content_directory": "$CONTENT_DIR",
  "total_files": $TOTAL_FILES,
  "html_violations": $VIOLATIONS,
  "critical_violations": $CRITICAL_VIOLATIONS,
  "policy": {
    "zero_html": "enforced",
    "allowed_markup": ["markdown_only", "no_raw_html"],
    "blocked_patterns": [
      "script_tags",
      "event_handlers", 
      "javascript_urls",
      "iframe_tags",
      "object_tags",
      "embed_tags",
      "form_tags",
      "style_tags",
      "data_urls_non_image"
    ]
  },
  "enforcement": {
    "ci_blocking": true,
    "zero_tolerance": true,
    "remediation_required": $([ $VIOLATIONS -gt 0 ] && echo "true" || echo "false")
  }
}
EOF

# Create sanitized versions if violations found
if [ $VIOLATIONS -gt 0 ]; then
    echo
    echo -e "${BLUE}Creating sanitized versions...${NC}"
    
    mkdir -p "${CONTENT_DIR}_sanitized"
    
    while IFS= read -r -d '' file; do
        relative_path=${file#$CONTENT_DIR/}
        sanitized_file="${CONTENT_DIR}_sanitized/$relative_path"
        sanitized_dir=$(dirname "$sanitized_file")
        
        mkdir -p "$sanitized_dir"
        
        # Create sanitized version by removing all HTML
        sed -E \
            -e 's/<[^>]*>//g' \
            -e 's/javascript:[^"]*//g' \
            -e 's/on[a-zA-Z]+\s*=\s*"[^"]*"//g' \
            -e "s/on[a-zA-Z]+\s*=\s*'[^']*'//g" \
            "$file" > "$sanitized_file"
            
        echo "   Created: $sanitized_file"
    done < <(find "$CONTENT_DIR" -name "*.md" -type f -print0)
    
    echo -e "${GREEN}✅ Sanitized versions created in: ${CONTENT_DIR}_sanitized${NC}"
fi

echo
if [ $CRITICAL_VIOLATIONS -gt 0 ]; then
    echo -e "${RED}❌ CRITICAL SECURITY VIOLATIONS DETECTED${NC}"
    echo "Build MUST fail - critical HTML patterns found in Markdown"
    echo "These patterns pose immediate security risks:"
    echo "- <script> tags (XSS risk)"
    echo "- Event handlers (XSS risk)" 
    echo "- javascript: URLs (XSS risk)"
    echo "- <iframe>, <object>, <embed> tags (injection risk)"
    echo
    echo "🔧 To fix:"
    echo "1. Remove all HTML from Markdown files"
    echo "2. Use pure Markdown syntax only"  
    echo "3. Use sanitized versions from ${CONTENT_DIR}_sanitized/"
    exit 2
elif [ $VIOLATIONS -gt 0 ]; then
    echo -e "${RED}❌ HTML POLICY VIOLATIONS DETECTED${NC}" 
    echo "Build MUST fail - raw HTML found in Markdown"
    echo "SecureBlog enforces ZERO raw HTML policy"
    echo
    echo "🔧 To fix:"
    echo "1. Convert HTML to equivalent Markdown syntax"
    echo "2. Remove style tags and use CSS classes instead"
    echo "3. Use sanitized versions from ${CONTENT_DIR}_sanitized/"  
    echo "4. Ensure all content is pure Markdown"
    exit 1
else
    echo -e "${GREEN}✅ ALL MARKDOWN FILES ARE CLEAN${NC}"
    echo "No raw HTML found - zero HTML policy enforced"
    echo "All files contain pure Markdown only"
    exit 0
fi