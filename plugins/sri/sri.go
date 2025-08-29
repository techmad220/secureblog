package sri

import (
	"crypto/sha256"
	"crypto/sha384"
	"crypto/sha512"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
)

// Plugin adds Subresource Integrity (SRI) hashes to external resources
type Plugin struct{}

// ProcessHTML adds SRI hashes to any external CSS links
func (p *Plugin) ProcessHTML(html string) string {
	// Pattern to find external CSS links
	linkPattern := regexp.MustCompile(`<link[^>]*href=["'](https?://[^"']+\.css)["'][^>]*>`)
	
	return linkPattern.ReplaceAllStringFunc(html, func(match string) string {
		// Extract URL
		urlPattern := regexp.MustCompile(`href=["'](https?://[^"']+)["']`)
		urlMatch := urlPattern.FindStringSubmatch(match)
		if len(urlMatch) < 2 {
			return match
		}
		
		url := urlMatch[1]
		
		// Skip if already has integrity attribute
		if strings.Contains(match, "integrity=") {
			return match
		}
		
		// Generate SRI hash
		hash, err := generateSRIHash(url)
		if err != nil {
			// Log error but don't break the build
			fmt.Printf("Warning: Could not generate SRI for %s: %v\n", url, err)
			return match
		}
		
		// Add integrity and crossorigin attributes
		return strings.Replace(match, ">", 
			fmt.Sprintf(` integrity="%s" crossorigin="anonymous">`, hash), 1)
	})
}

// generateSRIHash fetches resource and generates SHA-384 hash
func generateSRIHash(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	
	// Use SHA-384 as recommended by W3C
	hasher := sha384.New()
	if _, err := io.Copy(hasher, resp.Body); err != nil {
		return "", err
	}
	
	hash := base64.StdEncoding.EncodeToString(hasher.Sum(nil))
	return fmt.Sprintf("sha384-%s", hash), nil
}

// GenerateSRIManifest creates a manifest of all external resources with their SRI hashes
func GenerateSRIManifest(resources []string) map[string]string {
	manifest := make(map[string]string)
	
	for _, url := range resources {
		hash, err := generateSRIHash(url)
		if err == nil {
			manifest[url] = hash
		}
	}
	
	return manifest
}