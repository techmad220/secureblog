package security

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"html"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
)

// GenerateNonce creates a secure random nonce for CSP
func GenerateNonce() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// SanitizeHTML removes potentially dangerous HTML
func SanitizeHTML(s string) string {
	// Remove script tags and event handlers
	s = strings.ReplaceAll(s, "<script", "&lt;script")
	s = strings.ReplaceAll(s, "</script>", "&lt;/script&gt;")
	s = strings.ReplaceAll(s, "javascript:", "")
	s = strings.ReplaceAll(s, "on", "&#111;n")
	return s
}

// EscapeHTML escapes HTML special characters
func EscapeHTML(s string) string {
	return html.EscapeString(s)
}

// EscapeXML escapes XML special characters
func EscapeXML(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	s = strings.ReplaceAll(s, "\"", "&quot;")
	s = strings.ReplaceAll(s, "'", "&apos;")
	return s
}

// SignBuild creates integrity hashes for all files
func SignBuild(outputDir string) error {
	manifest := make(map[string]string)

	err := filepath.Walk(outputDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}

		content, err := ioutil.ReadFile(path)
		if err != nil {
			return err
		}

		h := sha256.Sum256(content)
		hash := hex.EncodeToString(h[:])
		
		rel, _ := filepath.Rel(outputDir, path)
		manifest[rel] = hash

		return nil
	})

	if err != nil {
		return err
	}

	// Write manifest
	var manifestContent strings.Builder
	for file, hash := range manifest {
		manifestContent.WriteString(fmt.Sprintf("%s:%s\n", file, hash))
	}

	return ioutil.WriteFile(
		filepath.Join(outputDir, "integrity.txt"),
		[]byte(manifestContent.String()),
		0644,
	)
}

// VerifyBuild checks integrity of all files
func VerifyBuild(outputDir string) error {
	manifestPath := filepath.Join(outputDir, "integrity.txt")
	content, err := ioutil.ReadFile(manifestPath)
	if err != nil {
		return fmt.Errorf("reading manifest: %w", err)
	}

	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		if line == "" {
			continue
		}

		parts := strings.Split(line, ":")
		if len(parts) != 2 {
			continue
		}

		file, expectedHash := parts[0], parts[1]
		
		// Skip manifest itself
		if file == "integrity.txt" {
			continue
		}

		filePath := filepath.Join(outputDir, file)
		content, err := ioutil.ReadFile(filePath)
		if err != nil {
			return fmt.Errorf("reading %s: %w", file, err)
		}

		h := sha256.Sum256(content)
		actualHash := hex.EncodeToString(h[:])

		if actualHash != expectedHash {
			return fmt.Errorf("integrity check failed for %s", file)
		}
	}

	return nil
}

// GenerateHeaders creates security headers for web server
func GenerateHeaders(outputDir string) error {
	headers := `# Security Headers for Nginx/Apache/CloudFlare

# Content Security Policy - Maximum Security
Content-Security-Policy: default-src 'none'; style-src 'self'; img-src 'self' data:; form-action 'none'; frame-ancestors 'none'; base-uri 'none'; upgrade-insecure-requests

# Other Security Headers
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Referrer-Policy: no-referrer
Permissions-Policy: geolocation=(), microphone=(), camera=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()

# HSTS (if using HTTPS)
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload

# Remove server identification
Server: 
X-Powered-By: 
`
	
	return ioutil.WriteFile(
		filepath.Join(outputDir, "_headers"),
		[]byte(headers),
		0644,
	)
}