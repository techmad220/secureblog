package integrity

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// Plugin provides content integrity verification
type Plugin struct {
	enabled  bool
	manifest map[string]string
}

// Config holds plugin configuration
type Config struct {
	Enabled      bool   `json:"enabled"`
	ManifestPath string `json:"manifest_path"`
	SignKeyPath  string `json:"sign_key_path"`
}

// NewPlugin creates a new integrity plugin
func NewPlugin(config Config) *Plugin {
	return &Plugin{
		enabled:  config.Enabled,
		manifest: make(map[string]string),
	}
}

// GenerateManifest creates integrity manifest for all content
func (p *Plugin) GenerateManifest(contentDir string) error {
	if !p.enabled {
		return nil
	}
	
	err := filepath.Walk(contentDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		
		if info.IsDir() {
			return nil
		}
		
		// Skip manifest and signature files
		if filepath.Base(path) == "integrity-manifest.json" || 
		   filepath.Base(path) == "integrity-manifest.json.sig" {
			return nil
		}
		
		hash, err := p.hashFile(path)
		if err != nil {
			return fmt.Errorf("hashing %s: %w", path, err)
		}
		
		relPath, err := filepath.Rel(contentDir, path)
		if err != nil {
			return err
		}
		
		p.manifest[relPath] = hash
		return nil
	})
	
	if err != nil {
		return fmt.Errorf("walking directory: %w", err)
	}
	
	return nil
}

// hashFile computes SHA-256 hash of file
func (p *Plugin) hashFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	
	hasher := sha256.New()
	if _, err := io.Copy(hasher, file); err != nil {
		return "", err
	}
	
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

// SaveManifest writes manifest to file
func (p *Plugin) SaveManifest(outputPath string) error {
	if !p.enabled {
		return nil
	}
	
	// Add metadata
	manifestWithMeta := map[string]interface{}{
		"version":   "1.0",
		"generated": time.Now().UTC().Format(time.RFC3339),
		"files":     p.manifest,
	}
	
	data, err := json.MarshalIndent(manifestWithMeta, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling manifest: %w", err)
	}
	
	err = os.WriteFile(outputPath, data, 0644)
	if err != nil {
		return fmt.Errorf("writing manifest: %w", err)
	}
	
	return nil
}

// VerifyFile checks file integrity against manifest
func (p *Plugin) VerifyFile(path string, content []byte) (bool, error) {
	if !p.enabled {
		return true, nil
	}
	
	expectedHash, exists := p.manifest[path]
	if !exists {
		return false, fmt.Errorf("file not in manifest: %s", path)
	}
	
	hasher := sha256.New()
	hasher.Write(content)
	actualHash := hex.EncodeToString(hasher.Sum(nil))
	
	// Use constant-time comparison to prevent timing attacks
	if subtle.ConstantTimeCompare([]byte(expectedHash), []byte(actualHash)) != 1 {
		return false, fmt.Errorf("hash mismatch for %s", path)
	}
	
	return true, nil
}

// LoadManifest reads manifest from file
func (p *Plugin) LoadManifest(manifestPath string) error {
	if !p.enabled {
		return nil
	}
	
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		return fmt.Errorf("reading manifest: %w", err)
	}
	
	var manifestWithMeta struct {
		Version   string            `json:"version"`
		Generated string            `json:"generated"`
		Files     map[string]string `json:"files"`
	}
	
	err = json.Unmarshal(data, &manifestWithMeta)
	if err != nil {
		return fmt.Errorf("parsing manifest: %w", err)
	}
	
	p.manifest = manifestWithMeta.Files
	return nil
}

// VerifyAll checks all files in directory against manifest
func (p *Plugin) VerifyAll(contentDir string) error {
	if !p.enabled {
		return nil
	}
	
	verified := make(map[string]bool)
	
	// Check all files in manifest exist and match
	for relPath, expectedHash := range p.manifest {
		fullPath := filepath.Join(contentDir, relPath)
		
		actualHash, err := p.hashFile(fullPath)
		if err != nil {
			return fmt.Errorf("file missing or inaccessible: %s", relPath)
		}
		
		if subtle.ConstantTimeCompare([]byte(expectedHash), []byte(actualHash)) != 1 {
			return fmt.Errorf("integrity check failed for: %s", relPath)
		}
		
		verified[relPath] = true
	}
	
	// Check for unexpected files
	err := filepath.Walk(contentDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		
		relPath, _ := filepath.Rel(contentDir, path)
		
		// Skip manifest files
		if filepath.Base(path) == "integrity-manifest.json" ||
		   filepath.Base(path) == "integrity-manifest.json.sig" {
			return nil
		}
		
		if !verified[relPath] {
			return fmt.Errorf("unexpected file not in manifest: %s", relPath)
		}
		
		return nil
	})
	
	return err
}