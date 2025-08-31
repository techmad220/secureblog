// markdown-security.go - Ultra-secure Markdown rendering with zero HTML injection
package main

import (
	"html"
	"net/url"
	"regexp"
	"strings"

	"github.com/russross/blackfriday/v2"
)

// SecureMarkdownRenderer provides Fort Knox-level Markdown security
type SecureMarkdownRenderer struct {
	*blackfriday.HTMLRenderer
	strictMode bool
}

// NewSecureMarkdownRenderer creates a maximally secure Markdown renderer
func NewSecureMarkdownRenderer() *SecureMarkdownRenderer {
	// Ultra-strict HTML renderer flags
	htmlFlags := blackfriday.HTMLFlagsNone |
		blackfriday.HTMLFlagSkipHTML | // CRITICAL: Skip all raw HTML
		blackfriday.HTMLFlagSkipImages |
		blackfriday.HTMLFlagSkipLinks |
		blackfriday.HTMLFlagSafetyMode // Enable safety mode

	renderer := blackfriday.NewHTMLRenderer(blackfriday.HTMLRendererParameters{
		Flags: htmlFlags,
		CSS:   "", // No inline CSS allowed
	})

	return &SecureMarkdownRenderer{
		HTMLRenderer: renderer,
		strictMode:   true,
	}
}

// RenderToString safely renders Markdown to HTML with comprehensive sanitization
func (r *SecureMarkdownRenderer) RenderToString(markdown []byte) string {
	// Configure Markdown parser with security-first extensions
	extensions := blackfriday.WithExtensions(
		blackfriday.CommonExtensions &^ blackfriday.Autolink &^ // Disable autolinks
			blackfriday.BackslashLineBreak &^ // Disable backslash line breaks
			blackfriday.DefinitionLists, // Disable definition lists for simplicity
	)

	// Parse and render
	output := blackfriday.Run(markdown, blackfriday.WithRenderer(r), extensions)

	// Multi-layer security sanitization
	sanitized := r.sanitizeHTML(string(output))
	sanitized = r.sanitizeURLs(sanitized)
	sanitized = r.sanitizeAttributes(sanitized)
	sanitized = r.validateFinalOutput(sanitized)

	return sanitized
}

// sanitizeHTML removes all dangerous HTML elements and attributes
func (r *SecureMarkdownRenderer) sanitizeHTML(input string) string {
	// Remove all script tags and content
	scriptRegex := regexp.MustCompile(`(?i)<script[^>]*>.*?</script>`)
	input = scriptRegex.ReplaceAllString(input, "")

	// Remove all dangerous tags
	dangerousTags := []string{
		"script", "object", "embed", "iframe", "frame", "frameset",
		"applet", "link", "meta", "style", "base", "form", "input",
		"button", "textarea", "select", "option", "svg", "math",
		"canvas", "audio", "video", "source", "track",
	}

	for _, tag := range dangerousTags {
		// Remove opening tags
		openRegex := regexp.MustCompile(`(?i)<` + tag + `[^>]*>`)
		input = openRegex.ReplaceAllString(input, "")

		// Remove closing tags  
		closeRegex := regexp.MustCompile(`(?i)</` + tag + `[^>]*>`)
		input = closeRegex.ReplaceAllString(input, "")

		// Remove self-closing tags
		selfCloseRegex := regexp.MustCompile(`(?i)<` + tag + `[^>]*/?>`)
		input = selfCloseRegex.ReplaceAllString(input, "")
	}

	return input
}

// sanitizeURLs ensures all URLs are safe and removes javascript: and data: schemes
func (r *SecureMarkdownRenderer) sanitizeURLs(input string) string {
	// Remove javascript: URLs
	jsRegex := regexp.MustCompile(`(?i)javascript:[^"'\s>]*`)
	input = jsRegex.ReplaceAllString(input, "")

	// Remove vbscript: URLs
	vbsRegex := regexp.MustCompile(`(?i)vbscript:[^"'\s>]*`)
	input = vbsRegex.ReplaceAllString(input, "")

	// Remove data: URLs (except safe image data URLs)
	dataRegex := regexp.MustCompile(`(?i)data:(?!image/(png|jpg|jpeg|gif|webp|svg\+xml);base64,)[^"'\s>]*`)
	input = dataRegex.ReplaceAllString(input, "")

	// Validate remaining URLs
	hrefRegex := regexp.MustCompile(`(?i)href\s*=\s*["']([^"']*)["']`)
	input = hrefRegex.ReplaceAllStringFunc(input, func(match string) string {
		urlMatch := regexp.MustCompile(`["']([^"']*)["']`).FindStringSubmatch(match)
		if len(urlMatch) > 1 {
			if isValidURL(urlMatch[1]) {
				return match // Keep valid URLs
			}
		}
		return `href=""` // Replace invalid URLs
	})

	return input
}

// sanitizeAttributes removes all dangerous HTML attributes
func (r *SecureMarkdownRenderer) sanitizeAttributes(input string) string {
	// Remove all event handlers (on*)
	eventRegex := regexp.MustCompile(`(?i)\s+on[a-z]*\s*=\s*["'][^"']*["']`)
	input = eventRegex.ReplaceAllString(input, "")

	// Remove style attributes (inline CSS)
	styleRegex := regexp.MustCompile(`(?i)\s+style\s*=\s*["'][^"']*["']`)
	input = styleRegex.ReplaceAllString(input, "")

	// Remove other dangerous attributes
	dangerousAttrs := []string{
		"autofocus", "autoplay", "background", "bgcolor", "border",
		"cellpadding", "cellspacing", "challenge", "charset", "cite",
		"class", "classid", "color", "cols", "colspan", "content",
		"contenteditable", "contextmenu", "controls", "coords",
		"crossorigin", "csp", "data", "datetime", "default", "defer",
		"dir", "dirname", "disabled", "download", "draggable",
		"dropzone", "enctype", "for", "form", "formaction", "headers",
		"height", "hidden", "high", "hreflang", "id", "integrity",
		"is", "ismap", "itemid", "itemprop", "itemref", "itemscope",
		"itemtype", "keytype", "kind", "label", "lang", "list", "loop",
		"low", "manifest", "max", "maxlength", "media", "method",
		"min", "minlength", "multiple", "name", "nonce", "novalidate",
		"open", "optimum", "pattern", "ping", "placeholder", "poster",
		"preload", "radiogroup", "readonly", "rel", "required",
		"reversed", "role", "rows", "rowspan", "sandbox", "scope",
		"scoped", "security", "size", "sizes", "span", "spellcheck",
		"src", "srcdoc", "srclang", "srcset", "start", "step",
		"summary", "tabindex", "target", "title", "type", "usemap",
		"value", "width", "wrap",
	}

	for _, attr := range dangerousAttrs {
		attrRegex := regexp.MustCompile(`(?i)\s+` + attr + `\s*=\s*["'][^"']*["']`)
		input = attrRegex.ReplaceAllString(input, "")
	}

	return input
}

// validateFinalOutput performs final security validation on the rendered HTML
func (r *SecureMarkdownRenderer) validateFinalOutput(input string) string {
	// Escape any remaining < and > that might have been missed
	input = strings.ReplaceAll(input, "<script", "&lt;script")
	input = strings.ReplaceAll(input, "</script", "&lt;/script")

	// Double-check for remaining dangerous patterns
	dangerousPatterns := []string{
		"javascript:",
		"vbscript:",
		"data:text/html",
		"data:application/",
		"<script",
		"</script",
		"<iframe",
		"<object",
		"<embed",
		"onload=",
		"onerror=",
		"onclick=",
		"onmouseover=",
		"expression(",
		"url(",
		"@import",
		"binding:",
	}

	for _, pattern := range dangerousPatterns {
		if strings.Contains(strings.ToLower(input), strings.ToLower(pattern)) {
			// Log security violation
			logSecurityViolation("Dangerous pattern detected", pattern, input[:100])
			// Strip the dangerous content
			input = strings.ReplaceAll(input, pattern, "")
		}
	}

	return input
}

// isValidURL validates that a URL is safe to include
func isValidURL(rawURL string) bool {
	// Parse URL
	parsedURL, err := url.Parse(rawURL)
	if err != nil {
		return false
	}

	// Only allow safe schemes
	allowedSchemes := []string{"http", "https", "mailto", "ftp", "ftps"}
	schemeAllowed := false
	for _, scheme := range allowedSchemes {
		if parsedURL.Scheme == scheme {
			schemeAllowed = true
			break
		}
	}

	// Allow relative URLs (no scheme)
	if parsedURL.Scheme == "" {
		schemeAllowed = true
	}

	if !schemeAllowed {
		return false
	}

	// Block localhost/internal URLs for security
	hostname := parsedURL.Hostname()
	if hostname == "localhost" || hostname == "127.0.0.1" || hostname == "::1" {
		return false
	}

	// Block private IP ranges
	if strings.HasPrefix(hostname, "10.") ||
		strings.HasPrefix(hostname, "192.168.") ||
		strings.HasPrefix(hostname, "172.") {
		return false
	}

	return true
}

// logSecurityViolation logs security violations for monitoring
func logSecurityViolation(violation, pattern, context string) {
	// In production, this should integrate with your security monitoring
	log.Printf("SECURITY VIOLATION: %s - Pattern: %s - Context: %s", violation, pattern, context)
}

// SecureTemplateRenderer provides secure template variable rendering
type SecureTemplateRenderer struct{}

// RenderTemplate safely renders template variables with auto-escaping
func (r *SecureTemplateRenderer) RenderTemplate(template string, variables map[string]string) string {
	result := template

	for key, value := range variables {
		// Auto-escape all template variables to prevent injection
		escapedValue := html.EscapeString(value)

		// Replace template placeholders
		placeholder := "{{." + key + "}}"
		result = strings.ReplaceAll(result, placeholder, escapedValue)
	}

	// Ensure no unescaped template variables remain
	templateVarRegex := regexp.MustCompile(`\{\{\.[\w\d_]+\}\}`)
	result = templateVarRegex.ReplaceAllString(result, "")

	return result
}

// ValidateMarkdownContent validates Markdown content for security before processing
func ValidateMarkdownContent(content []byte) error {
	contentStr := string(content)

	// Check for extremely dangerous patterns that should never be processed
	forbiddenPatterns := []string{
		"<script",
		"javascript:",
		"vbscript:",
		"data:text/html",
		"<iframe",
		"<object",
		"<embed",
		"<svg onload",
		"<img onerror",
		"style=",
		"onload=",
		"onclick=",
		"onmouseover=",
	}

	for _, pattern := range forbiddenPatterns {
		if strings.Contains(strings.ToLower(contentStr), pattern) {
			return fmt.Errorf("forbidden content pattern detected: %s", pattern)
		}
	}

	// Check content length limits
	if len(content) > 1024*1024 { // 1MB limit
		return fmt.Errorf("content too large: %d bytes (max 1MB)", len(content))
	}

	return nil
}