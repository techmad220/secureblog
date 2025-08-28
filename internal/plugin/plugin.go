package plugin

import (
	"html/template"
	"io/fs"
)

// Plugin is the base interface all plugins must implement
type Plugin interface {
	Name() string
	Version() string
	Init(config map[string]interface{}) error
	Priority() int // Lower numbers run first
}

// ContentPlugin processes content during build
type ContentPlugin interface {
	Plugin
	ProcessContent(content []byte, metadata map[string]interface{}) ([]byte, error)
}

// RenderPlugin modifies HTML rendering
type RenderPlugin interface {
	Plugin
	PreRender(data interface{}) (interface{}, error)
	PostRender(html []byte) ([]byte, error)
}

// SecurityPlugin adds security features
type SecurityPlugin interface {
	Plugin
	ApplySecurity(content []byte) ([]byte, error)
	GenerateHeaders() map[string]string
}

// BuildPlugin hooks into build process
type BuildPlugin interface {
	Plugin
	PreBuild(sourceDir string) error
	PostBuild(outputDir string) error
}

// OutputPlugin generates additional output formats
type OutputPlugin interface {
	Plugin
	Generate(posts []Post, outputDir string) error
}

// Post represents a blog post
type Post struct {
	Title       string
	Content     template.HTML
	RawContent  []byte
	Date        string
	Slug        string
	Tags        []string
	Metadata    map[string]interface{}
	Hash        string
}

// PluginManager manages all plugins
type PluginManager struct {
	contentPlugins  []ContentPlugin
	renderPlugins   []RenderPlugin
	securityPlugins []SecurityPlugin
	buildPlugins    []BuildPlugin
	outputPlugins   []OutputPlugin
	config          map[string]interface{}
}

// NewPluginManager creates a new plugin manager
func NewPluginManager() *PluginManager {
	return &PluginManager{
		contentPlugins:  []ContentPlugin{},
		renderPlugins:   []RenderPlugin{},
		securityPlugins: []SecurityPlugin{},
		buildPlugins:    []BuildPlugin{},
		outputPlugins:   []OutputPlugin{},
		config:          make(map[string]interface{}),
	}
}

// Register adds a plugin to the manager
func (pm *PluginManager) Register(plugin interface{}) error {
	switch p := plugin.(type) {
	case ContentPlugin:
		pm.contentPlugins = append(pm.contentPlugins, p)
	case RenderPlugin:
		pm.renderPlugins = append(pm.renderPlugins, p)
	case SecurityPlugin:
		pm.securityPlugins = append(pm.securityPlugins, p)
	case BuildPlugin:
		pm.buildPlugins = append(pm.buildPlugins, p)
	case OutputPlugin:
		pm.outputPlugins = append(pm.outputPlugins, p)
	}
	return nil
}

// LoadPlugin dynamically loads a plugin from a file
func (pm *PluginManager) LoadPlugin(path string) error {
	// Go plugins would use plugin.Open() here
	// For security, we'll use compiled-in plugins instead
	return nil
}

// ProcessContent runs all content plugins
func (pm *PluginManager) ProcessContent(content []byte, metadata map[string]interface{}) ([]byte, error) {
	var err error
	for _, plugin := range pm.contentPlugins {
		content, err = plugin.ProcessContent(content, metadata)
		if err != nil {
			return nil, err
		}
	}
	return content, nil
}

// PreRender runs all pre-render plugins
func (pm *PluginManager) PreRender(data interface{}) (interface{}, error) {
	var err error
	for _, plugin := range pm.renderPlugins {
		data, err = plugin.PreRender(data)
		if err != nil {
			return nil, err
		}
	}
	return data, nil
}

// PostRender runs all post-render plugins
func (pm *PluginManager) PostRender(html []byte) ([]byte, error) {
	var err error
	for _, plugin := range pm.renderPlugins {
		html, err = plugin.PostRender(html)
		if err != nil {
			return nil, err
		}
	}
	return html, nil
}

// ApplySecurity runs all security plugins
func (pm *PluginManager) ApplySecurity(content []byte) ([]byte, error) {
	var err error
	for _, plugin := range pm.securityPlugins {
		content, err = plugin.ApplySecurity(content)
		if err != nil {
			return nil, err
		}
	}
	return content, nil
}

// GetSecurityHeaders collects headers from all security plugins
func (pm *PluginManager) GetSecurityHeaders() map[string]string {
	headers := make(map[string]string)
	for _, plugin := range pm.securityPlugins {
		for k, v := range plugin.GenerateHeaders() {
			headers[k] = v
		}
	}
	return headers
}

// PreBuild runs all pre-build hooks
func (pm *PluginManager) PreBuild(sourceDir string) error {
	for _, plugin := range pm.buildPlugins {
		if err := plugin.PreBuild(sourceDir); err != nil {
			return err
		}
	}
	return nil
}

// PostBuild runs all post-build hooks
func (pm *PluginManager) PostBuild(outputDir string) error {
	for _, plugin := range pm.buildPlugins {
		if err := plugin.PostBuild(outputDir); err != nil {
			return err
		}
	}
	return nil
}

// GenerateOutputs runs all output plugins
func (pm *PluginManager) GenerateOutputs(posts []Post, outputDir string) error {
	for _, plugin := range pm.outputPlugins {
		if err := plugin.Generate(posts, outputDir); err != nil {
			return err
		}
	}
	return nil
}

// PluginFS allows plugins to provide their own templates/assets
type PluginFS interface {
	Plugin
	GetFS() fs.FS
}