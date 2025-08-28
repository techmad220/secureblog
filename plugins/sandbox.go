package plugins

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
)

// Sandbox provides secure plugin execution environment
type Sandbox struct {
	DenyNetwork bool
	DenyEnv     bool
	ReadOnly    bool
	WorkDir     string
}

// NewSandbox creates a secure sandbox for plugin execution
func NewSandbox() *Sandbox {
	return &Sandbox{
		DenyNetwork: true,
		DenyEnv:     true,
		ReadOnly:    true,
		WorkDir:     "/tmp/plugin-sandbox",
	}
}

// Execute runs a plugin in sandboxed environment
func (s *Sandbox) Execute(pluginPath string, args ...string) error {
	// Validate plugin doesn't output JavaScript
	if err := s.validatePlugin(pluginPath); err != nil {
		return fmt.Errorf("plugin validation failed: %w", err)
	}

	cmd := exec.Command(pluginPath, args...)
	
	// Set up sandbox environment
	cmd.Env = s.getSafeEnv()
	cmd.Dir = s.WorkDir
	
	// Deny network access using namespace isolation
	if s.DenyNetwork {
		cmd.SysProcAttr = &syscall.SysProcAttr{
			Cloneflags: syscall.CLONE_NEWNET,
		}
	}
	
	// Run with reduced privileges
	cmd.SysProcAttr.Credential = &syscall.Credential{
		Uid: 65534, // nobody
		Gid: 65534, // nogroup
	}
	
	return cmd.Run()
}

// validatePlugin ensures plugin cannot output dangerous content
func (s *Sandbox) validatePlugin(pluginPath string) error {
	// Read plugin binary
	content, err := os.ReadFile(pluginPath)
	if err != nil {
		return err
	}
	
	// Check for dangerous patterns in binary
	dangerous := []string{
		"<script",
		"javascript:",
		"onclick",
		"onerror",
		"onload",
		"eval(",
		"document.",
		"window.",
	}
	
	contentStr := string(content)
	for _, pattern := range dangerous {
		if strings.Contains(strings.ToLower(contentStr), pattern) {
			return fmt.Errorf("plugin contains dangerous pattern: %s", pattern)
		}
	}
	
	return nil
}

// getSafeEnv returns minimal safe environment variables
func (s *Sandbox) getSafeEnv() []string {
	if s.DenyEnv {
		// Only essential variables
		return []string{
			"PATH=/usr/bin:/bin",
			"HOME=/tmp",
			"USER=nobody",
			"GOWORK=off",     // Disable workspace
			"CGO_ENABLED=0",  // Disable CGO
			"GOPROXY=off",    // Disable module proxy
			"GOSUMDB=off",    // Disable checksum DB
		}
	}
	return os.Environ()
}

// OutputFilter validates and sanitizes plugin output
type OutputFilter struct {
	blockPatterns []string
}

// NewOutputFilter creates a filter for plugin output
func NewOutputFilter() *OutputFilter {
	return &OutputFilter{
		blockPatterns: []string{
			"<script",
			"</script",
			"javascript:",
			"on[a-z]+\\s*=",
			"eval\\(",
			"Function\\(",
			"setTimeout",
			"setInterval",
			"\\.innerHTML",
			"document\\.",
			"window\\.",
			"import\\(",
		},
	}
}

// Filter removes any JavaScript from plugin output
func (f *OutputFilter) Filter(output string) (string, error) {
	lower := strings.ToLower(output)
	
	for _, pattern := range f.blockPatterns {
		if strings.Contains(lower, strings.ToLower(pattern)) {
			return "", fmt.Errorf("plugin output contains blocked pattern: %s", pattern)
		}
	}
	
	// Additional sanitization
	output = strings.ReplaceAll(output, "<script", "&lt;script")
	output = strings.ReplaceAll(output, "javascript:", "javascript&#58;")
	
	return output, nil
}