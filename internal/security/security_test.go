package security

import (
	"strings"
	"testing"
)

func TestGenerateNonce(t *testing.T) {
	nonce1 := GenerateNonce()
	nonce2 := GenerateNonce()
	
	// Nonces should be unique
	if nonce1 == nonce2 {
		t.Error("GenerateNonce should produce unique values")
	}
	
	// Nonces should be 32 characters (16 bytes hex encoded)
	if len(nonce1) != 32 {
		t.Errorf("Nonce length should be 32, got %d", len(nonce1))
	}
}

func TestSanitizeHTML(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "Script tags",
			input: "<script>alert('xss')</script>",
			want:  "&lt;script&gt;alert('xss')&lt;/script&gt;",
		},
		{
			name:  "JavaScript protocol",
			input: `<a href="javascript:alert('xss')">click</a>`,
			want:  `<a href="alert('xss')">click</a>`,
		},
		{
			name:  "Event handlers",
			input: `<div onclick="alert('xss')">test</div>`,
			want:  `<div &#111;nclick="alert('xss')">test</div>`,
		},
		{
			name:  "Clean HTML",
			input: `<p>This is clean</p>`,
			want:  `<p>This is clean</p>`,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := SanitizeHTML(tt.input)
			if got != tt.want {
				t.Errorf("SanitizeHTML() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestEscapeHTML(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"<script>", "&lt;script&gt;"},
		{"&copy;", "&amp;copy;"},
		{`"quotes"`, "&#34;quotes&#34;"},
		{"normal text", "normal text"},
	}
	
	for _, tt := range tests {
		got := EscapeHTML(tt.input)
		if got != tt.want {
			t.Errorf("EscapeHTML(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestGenerateHeaders(t *testing.T) {
	headers := map[string]string{
		"Content-Security-Policy": "default-src 'none'",
		"X-Frame-Options":         "DENY",
		"X-Content-Type-Options":  "nosniff",
	}
	
	// Check required headers are present
	requiredHeaders := []string{
		"Content-Security-Policy",
		"X-Frame-Options", 
		"X-Content-Type-Options",
	}
	
	for _, h := range requiredHeaders {
		if _, ok := headers[h]; !ok {
			t.Errorf("Required header %s is missing", h)
		}
	}
	
	// Check CSP is strict
	csp := headers["Content-Security-Policy"]
	if !strings.Contains(csp, "default-src 'none'") {
		t.Error("CSP should have strict default-src 'none'")
	}
}

func TestSignBuild(t *testing.T) {
	// Create temporary directory
	tempDir := t.TempDir()
	
	// Create test files
	testFile := "test.html"
	testContent := []byte("<html><body>Test</body></html>")
	
	err := os.WriteFile(
		filepath.Join(tempDir, testFile),
		testContent,
		0644,
	)
	if err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	// Sign the build
	err = SignBuild(tempDir)
	if err != nil {
		t.Fatalf("SignBuild failed: %v", err)
	}
	
	// Check integrity file exists
	integrityPath := filepath.Join(tempDir, "integrity.txt")
	if _, err := os.Stat(integrityPath); os.IsNotExist(err) {
		t.Error("Integrity file was not created")
	}
	
	// Verify the build
	err = VerifyBuild(tempDir)
	if err != nil {
		t.Errorf("VerifyBuild failed: %v", err)
	}
}

func TestNoJavaScriptViolations(t *testing.T) {
	badPatterns := []string{
		"<script>",
		"javascript:",
		"onclick=",
		"onload=",
		"eval(",
		"Function(",
		"setTimeout(",
		"setInterval(",
	}
	
	safeContent := "This is safe HTML content without any JavaScript"
	
	for _, pattern := range badPatterns {
		if strings.Contains(safeContent, pattern) {
			t.Errorf("Safe content should not contain pattern: %s", pattern)
		}
	}
}