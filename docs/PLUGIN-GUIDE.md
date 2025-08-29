# Plugin System Guide

## Overview

SecureBlog uses a plugin architecture to keep the core minimal while allowing extensibility. All plugins are **build-time only** - they cannot execute at runtime, maintaining our zero-JavaScript security model.

## How Plugins Work

1. **Discovery**: Plugins are discovered at build time from the `plugins/` directory
2. **Validation**: Each plugin is validated for security compliance (no network access, no file system writes outside build directory)
3. **Loading**: Plugins are loaded in priority order (lower numbers first)
4. **Execution**: Plugins run during the build process only
5. **Output**: Plugin results are baked into static HTML

## Plugin Types

### 1. Content Plugins
Process markdown and content during build.

**Example**: Syntax highlighting plugin
```go
// plugins/highlight/highlight.go
package highlight

import (
    "secureblog/internal/plugin"
    "github.com/alecthomas/chroma/v2"
)

type HighlightPlugin struct{}

func (p *HighlightPlugin) Name() string {
    return "syntax-highlighter"
}

func (p *HighlightPlugin) ProcessContent(content []byte, metadata map[string]interface{}) ([]byte, error) {
    // Process code blocks with syntax highlighting
    // This runs at BUILD TIME only - output is static HTML with CSS classes
    highlighted := highlightCodeBlocks(content)
    return highlighted, nil
}
```

### 2. Security Plugins
Add security features and headers.

**Example**: Subresource Integrity plugin
```go
// plugins/sri/sri.go
package sri

type SRIPlugin struct {
    hashes map[string]string
}

func (p *SRIPlugin) GenerateHeaders() map[string]string {
    return map[string]string{
        "X-Content-Hash": p.calculateHash(),
    }
}
```

### 3. Output Plugins
Generate additional output formats.

**Example**: JSON feed plugin
```go
// plugins/jsonfeed/jsonfeed.go
package jsonfeed

type JSONFeedPlugin struct{}

func (p *JSONFeedPlugin) Generate(posts []Post, outputDir string) error {
    feed := JSONFeed{
        Version: "1.1",
        Title:   "SecureBlog",
        Items:   convertPosts(posts),
    }
    
    data, _ := json.Marshal(feed)
    return ioutil.WriteFile(
        filepath.Join(outputDir, "feed.json"),
        data,
        0644,
    )
}
```

## Creating a Custom Plugin

### Step 1: Create Plugin Directory
```bash
mkdir plugins/myplugin
```

### Step 2: Implement Plugin Interface
```go
// plugins/myplugin/myplugin.go
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

// Implement one or more plugin interfaces...
```

### Step 3: Register in Main
```go
// cmd/main_v2.go
import "secureblog/plugins/myplugin"

// In main():
b.RegisterPlugin(myplugin.New())
```

## Plugin Security Rules

### ✅ Allowed
- Reading from content directory
- Writing to build output directory
- Processing markdown/HTML
- Generating static files
- Adding security headers

### ❌ Forbidden
- Network requests (enforced by sandbox)
- Writing outside build directory
- Executing external commands
- Loading dynamic code
- Runtime execution (all plugins are build-time only)

## Available Plugins

### Core Plugins (included)

| Plugin | Purpose | Priority |
|--------|---------|----------|
| `markdown` | Convert Markdown to HTML | 10 |
| `csp-security` | Add CSP headers | 1 |
| `integrity` | SHA-256 content hashing | 100 |
| `rss` | Generate RSS feed | 50 |
| `sitemap` | Generate XML sitemap | 51 |
| `cloudflare-analytics` | Privacy-first analytics | 80 |

### Community Plugins

| Plugin | Purpose | Repository |
|--------|---------|------------|
| `image-optimize` | Compress images | `github.com/user/secureblog-imageopt` |
| `search-index` | Generate search index | `github.com/user/secureblog-search` |
| `webmentions` | Process webmentions | `github.com/user/secureblog-webmentions` |

## Plugin Configuration

Configure plugins in `config.yaml`:

```yaml
plugins:
  markdown:
    enabled: true
    extensions:
      - tables
      - footnotes
      - strikethrough
  
  csp-security:
    enabled: true
    strict: true
    nonce: auto
  
  integrity:
    enabled: true
    algorithm: sha256
    sign: true
  
  myplugin:
    enabled: true
    custom_option: value
```

## Testing Plugins

```bash
# Test plugin in isolation
go test ./plugins/myplugin

# Test with security sandbox
GOWORK=off GOPROXY=off go test ./plugins/myplugin

# Integration test
go run cmd/main_v2.go -content=test-content -output=test-build
```

## Plugin Development Tips

1. **Keep it simple** - Plugins should do one thing well
2. **No side effects** - Plugins must be pure functions
3. **Document config** - Clearly document all configuration options
4. **Test thoroughly** - Include unit tests with your plugin
5. **Security first** - Never bypass security constraints

## Example: Table of Contents Plugin

Here's a complete example of a TOC plugin:

```go
// plugins/toc/toc.go
package toc

import (
    "bytes"
    "regexp"
    "secureblog/internal/plugin"
)

type TOCPlugin struct{}

func New() *TOCPlugin {
    return &TOCPlugin{}
}

func (p *TOCPlugin) Name() string {
    return "table-of-contents"
}

func (p *TOCPlugin) Version() string {
    return "1.0.0"
}

func (p *TOCPlugin) Priority() int {
    return 20 // Run after markdown
}

func (p *TOCPlugin) ProcessContent(content []byte, metadata map[string]interface{}) ([]byte, error) {
    // Find all headings
    headingRegex := regexp.MustCompile(`<h([2-6]).*?>(.*?)</h[2-6]>`)
    matches := headingRegex.FindAllSubmatch(content, -1)
    
    if len(matches) == 0 {
        return content, nil
    }
    
    // Build TOC
    var toc bytes.Buffer
    toc.WriteString("<nav class=\"toc\">\n<h2>Table of Contents</h2>\n<ul>\n")
    
    for _, match := range matches {
        level := string(match[1])
        text := string(match[2])
        id := slugify(text)
        
        // Add ID to heading
        content = bytes.Replace(
            content,
            match[0],
            []byte(fmt.Sprintf(`<h%s id="%s">%s</h%s>`, level, id, text, level)),
            1,
        )
        
        // Add to TOC
        toc.WriteString(fmt.Sprintf(`<li><a href="#%s">%s</a></li>`, id, text))
    }
    
    toc.WriteString("</ul>\n</nav>\n")
    
    // Insert TOC after first paragraph
    return insertTOC(content, toc.Bytes()), nil
}

func slugify(text string) string {
    // Convert to URL-safe slug
    reg := regexp.MustCompile(`[^a-z0-9-]`)
    return reg.ReplaceAllString(strings.ToLower(text), "-")
}
```

## Troubleshooting

### Plugin not loading
- Check plugin is in `plugins/` directory
- Verify it implements required interface
- Check for compile errors: `go build ./plugins/...`

### Plugin not executing
- Check priority conflicts
- Verify plugin is registered in main
- Check config.yaml for `enabled: true`

### Security violations
- Remove network calls
- Remove external command execution
- Ensure only writing to output directory

## Contributing a Plugin

1. Create plugin following guidelines
2. Include comprehensive tests
3. Document configuration options
4. Submit PR with example usage
5. Ensure it passes security audit

## Questions?

Open an issue on GitHub with the `plugin` label.