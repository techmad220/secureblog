# Plugin Development Guide

## Creating a New Plugin

Plugins extend SecureBlog's functionality without modifying core code.

## Plugin Types

### 1. Content Plugin
Process content during build (markdown, syntax highlighting, etc.)

```go
type MyContentPlugin struct{}

func (p *MyContentPlugin) ProcessContent(content []byte, metadata map[string]interface{}) ([]byte, error) {
    // Process content
    return modifiedContent, nil
}
```

### 2. Security Plugin
Add security features and headers

```go
type MySecurityPlugin struct{}

func (p *MySecurityPlugin) ApplySecurity(content []byte) ([]byte, error) {
    // Apply security transformations
    return securedContent, nil
}

func (p *MySecurityPlugin) GenerateHeaders() map[string]string {
    return map[string]string{
        "X-Custom-Header": "value",
    }
}
```

### 3. Output Plugin
Generate additional output formats (JSON, AMP, etc.)

```go
type MyOutputPlugin struct{}

func (p *MyOutputPlugin) Generate(posts []Post, outputDir string) error {
    // Generate custom output
    return nil
}
```

### 4. Build Plugin
Hook into build process

```go
type MyBuildPlugin struct{}

func (p *MyBuildPlugin) PreBuild(sourceDir string) error {
    // Run before build
    return nil
}

func (p *MyBuildPlugin) PostBuild(outputDir string) error {
    // Run after build
    return nil
}
```

## Plugin Structure

```go
package myplugin

import "secureblog/internal/plugin"

type MyPlugin struct {
    config map[string]interface{}
}

func New() *MyPlugin {
    return &MyPlugin{}
}

func (p *MyPlugin) Name() string {
    return "my-plugin"
}

func (p *MyPlugin) Version() string {
    return "1.0.0"
}

func (p *MyPlugin) Init(config map[string]interface{}) error {
    p.config = config
    return nil
}

func (p *MyPlugin) Priority() int {
    return 50 // 0-100, lower runs first
}
```

## Available Plugins

### Core Plugins

- **markdown** - Converts Markdown to secure HTML
- **csp-security** - Adds Content Security Policy
- **integrity** - SHA256 hashing for all content
- **rss** - RSS feed generation
- **sitemap** - XML sitemap generation

### Community Plugins

- **syntax-highlight** - Code syntax highlighting
- **image-optimize** - Image compression
- **minify** - HTML/CSS minification
- **analytics** - Privacy-focused analytics
- **search** - Static search index

## Installing Plugins

1. Place plugin in `plugins/` directory
2. Import in `cmd/main.go`
3. Register with builder

```go
import "secureblog/plugins/myplugin"

b.RegisterPlugin(myplugin.New())
```

## Plugin Configuration

Configure plugins in `config.yaml`:

```yaml
plugins:
  markdown:
    extensions:
      - tables
      - footnotes
  
  csp-security:
    strict: true
  
  rss:
    limit: 20
    full_content: false
```

## Security Guidelines

1. **No external network calls** during build
2. **No file system access** outside build directories
3. **Validate all input** from config and content
4. **Use secure defaults** always
5. **Document security implications**

## Example: Analytics Plugin

```go
package analytics

import (
    "fmt"
    "secureblog/internal/plugin"
)

type AnalyticsPlugin struct {
    config map[string]interface{}
}

func New() *AnalyticsPlugin {
    return &AnalyticsPlugin{}
}

func (p *AnalyticsPlugin) Name() string {
    return "privacy-analytics"
}

func (p *AnalyticsPlugin) Version() string {
    return "1.0.0"
}

func (p *AnalyticsPlugin) Init(config map[string]interface{}) error {
    p.config = config
    return nil
}

func (p *AnalyticsPlugin) Priority() int {
    return 90 // Run late
}

func (p *AnalyticsPlugin) PostRender(html []byte) ([]byte, error) {
    // Add privacy-focused analytics (no cookies, no tracking)
    analytics := `<img src="/pixel.gif" alt="" width="1" height="1" />`
    
    // Insert before </body>
    modified := bytes.Replace(html, 
        []byte("</body>"), 
        []byte(analytics + "</body>"), 
        1)
    
    return modified, nil
}

var _ plugin.RenderPlugin = (*AnalyticsPlugin)(nil)
```

## Testing Plugins

```bash
# Test plugin in isolation
go test ./plugins/myplugin

# Test with builder
go run cmd/main.go -plugins=./plugins
```

## Contributing

1. Follow security guidelines
2. Include tests
3. Document configuration
4. Provide examples
5. Submit PR with description