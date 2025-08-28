package security

import (
	"crypto/rand"
	"encoding/hex"
	"secureblog/internal/plugin"
	"strings"
)

// CSPPlugin adds Content Security Policy headers
type CSPPlugin struct {
	config map[string]interface{}
	nonce  string
}

func NewCSP() *CSPPlugin {
	return &CSPPlugin{}
}

func (p *CSPPlugin) Name() string {
	return "csp-security"
}

func (p *CSPPlugin) Version() string {
	return "1.0.0"
}

func (p *CSPPlugin) Init(config map[string]interface{}) error {
	p.config = config
	p.generateNonce()
	return nil
}

func (p *CSPPlugin) Priority() int {
	return 1 // Security runs first
}

func (p *CSPPlugin) generateNonce() {
	b := make([]byte, 16)
	rand.Read(b)
	p.nonce = hex.EncodeToString(b)
}

func (p *CSPPlugin) ApplySecurity(content []byte) ([]byte, error) {
	// Add nonce to inline styles if present
	html := string(content)
	html = strings.ReplaceAll(html, "<style>", `<style nonce="`+p.nonce+`">`)
	return []byte(html), nil
}

func (p *CSPPlugin) GenerateHeaders() map[string]string {
	return map[string]string{
		"Content-Security-Policy": "default-src 'none'; style-src 'self' 'nonce-" + p.nonce + "'; img-src 'self' data:; form-action 'none'; frame-ancestors 'none'; base-uri 'none'; upgrade-insecure-requests",
		"X-Frame-Options":         "DENY",
		"X-Content-Type-Options":  "nosniff",
		"X-XSS-Protection":        "1; mode=block",
		"Referrer-Policy":         "no-referrer",
		"Permissions-Policy":      "geolocation=(), microphone=(), camera=()",
	}
}

var _ plugin.SecurityPlugin = (*CSPPlugin)(nil)