package integrity

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"path/filepath"
	"secureblog/internal/plugin"
	"strings"
)

// IntegrityPlugin adds SHA256 hashes to all content
type IntegrityPlugin struct {
	config    map[string]interface{}
	manifest  map[string]string
}

func New() *IntegrityPlugin {
	return &IntegrityPlugin{
		manifest: make(map[string]string),
	}
}

func (p *IntegrityPlugin) Name() string {
	return "integrity-hash"
}

func (p *IntegrityPlugin) Version() string {
	return "1.0.0"
}

func (p *IntegrityPlugin) Init(config map[string]interface{}) error {
	p.config = config
	return nil
}

func (p *IntegrityPlugin) Priority() int {
	return 100 // Run last
}

func (p *IntegrityPlugin) PreBuild(sourceDir string) error {
	// Clear manifest for new build
	p.manifest = make(map[string]string)
	return nil
}

func (p *IntegrityPlugin) PostBuild(outputDir string) error {
	// Hash all output files
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
		p.manifest[rel] = hash

		return nil
	})

	if err != nil {
		return err
	}

	// Write integrity manifest
	var manifestContent strings.Builder
	manifestContent.WriteString("# Integrity Manifest\n")
	manifestContent.WriteString("# SHA256 hashes for all files\n\n")
	
	for file, hash := range p.manifest {
		manifestContent.WriteString(fmt.Sprintf("%s:%s\n", file, hash))
	}

	return ioutil.WriteFile(
		filepath.Join(outputDir, "integrity.txt"),
		[]byte(manifestContent.String()),
		0644,
	)
}

func (p *IntegrityPlugin) VerifyIntegrity(outputDir string) error {
	manifestPath := filepath.Join(outputDir, "integrity.txt")
	content, err := ioutil.ReadFile(manifestPath)
	if err != nil {
		return fmt.Errorf("reading manifest: %w", err)
	}

	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.Split(line, ":")
		if len(parts) != 2 {
			continue
		}

		file, expectedHash := parts[0], parts[1]
		
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

var _ plugin.BuildPlugin = (*IntegrityPlugin)(nil)