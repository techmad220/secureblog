package builder

import (
	"bytes"
	"fmt"
	"html/template"
	"io/ioutil"
	"os"
	"path/filepath"
	"secureblog/internal/plugin"
	"sort"
	"strings"
	"time"
)

// BuilderV2 is the plugin-based builder
type BuilderV2 struct {
	config        Config
	pluginManager *plugin.PluginManager
	posts         []plugin.Post
}

// NewV2 creates a plugin-based builder
func NewV2(config Config) *BuilderV2 {
	return &BuilderV2{
		config:        config,
		pluginManager: plugin.NewPluginManager(),
		posts:         []plugin.Post{},
	}
}

// RegisterPlugin adds a plugin to the builder
func (b *BuilderV2) RegisterPlugin(p interface{}) error {
	return b.pluginManager.Register(p)
}

// Build runs the build process with all plugins
func (b *BuilderV2) Build() error {
	// Pre-build hooks
	if err := b.pluginManager.PreBuild(b.config.ContentDir); err != nil {
		return fmt.Errorf("pre-build hooks failed: %w", err)
	}

	// Parse templates
	tmpl, err := b.parseTemplates()
	if err != nil {
		return fmt.Errorf("parsing templates: %w", err)
	}

	// Load and process posts
	if err := b.loadPosts(); err != nil {
		return fmt.Errorf("loading posts: %w", err)
	}

	// Generate HTML pages
	for _, post := range b.posts {
		if err := b.generatePost(tmpl, post); err != nil {
			return fmt.Errorf("generating post %s: %w", post.Slug, err)
		}
	}

	// Generate index
	if err := b.generateIndex(tmpl); err != nil {
		return fmt.Errorf("generating index: %w", err)
	}

	// Run output plugins (RSS, sitemap, etc.)
	if err := b.pluginManager.GenerateOutputs(b.posts, b.config.OutputDir); err != nil {
		return fmt.Errorf("generating outputs: %w", err)
	}

	// Copy static files
	if err := b.copyStatic(); err != nil {
		return fmt.Errorf("copying static files: %w", err)
	}

	// Generate security headers
	if err := b.generateSecurityHeaders(); err != nil {
		return fmt.Errorf("generating security headers: %w", err)
	}

	// Post-build hooks
	if err := b.pluginManager.PostBuild(b.config.OutputDir); err != nil {
		return fmt.Errorf("post-build hooks failed: %w", err)
	}

	return nil
}

func (b *BuilderV2) parseTemplates() (*template.Template, error) {
	tmpl := template.New("").Funcs(template.FuncMap{
		"truncate": func(s string, n int) string {
			if len(s) <= n {
				return s
			}
			return s[:n] + "..."
		},
	})

	return tmpl.ParseGlob(filepath.Join(b.config.TemplateDir, "*.html"))
}

func (b *BuilderV2) loadPosts() error {
	postsDir := filepath.Join(b.config.ContentDir, "posts")
	files, err := ioutil.ReadDir(postsDir)
	if err != nil {
		return err
	}

	for _, file := range files {
		if filepath.Ext(file.Name()) != ".md" {
			continue
		}

		content, err := ioutil.ReadFile(filepath.Join(postsDir, file.Name()))
		if err != nil {
			return err
		}

		// Extract metadata if present
		metadata := make(map[string]interface{})
		rawContent := content
		
		// Check for front matter
		if bytes.HasPrefix(content, []byte("---\n")) {
			parts := bytes.SplitN(content[4:], []byte("\n---\n"), 2)
			if len(parts) == 2 {
				// Parse YAML front matter here if needed
				rawContent = parts[1]
			}
		}

		// Process content through plugins
		processed, err := b.pluginManager.ProcessContent(rawContent, metadata)
		if err != nil {
			return err
		}

		// Apply security plugins
		secured, err := b.pluginManager.ApplySecurity(processed)
		if err != nil {
			return err
		}

		post := plugin.Post{
			Title:      strings.TrimSuffix(file.Name(), ".md"),
			Content:    template.HTML(secured),
			RawContent: rawContent,
			Date:       file.ModTime().Format(time.RFC3339),
			Slug:       strings.TrimSuffix(file.Name(), ".md"),
			Metadata:   metadata,
		}

		b.posts = append(b.posts, post)
	}

	// Sort posts by date (newest first)
	sort.Slice(b.posts, func(i, j int) bool {
		return b.posts[i].Date > b.posts[j].Date
	})

	return nil
}

func (b *BuilderV2) generatePost(tmpl *template.Template, post plugin.Post) error {
	outputPath := filepath.Join(b.config.OutputDir, post.Slug+".html")
	
	// Pre-render hook
	data, err := b.pluginManager.PreRender(post)
	if err != nil {
		return err
	}

	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, "post.html", data); err != nil {
		return err
	}

	// Post-render hook
	html, err := b.pluginManager.PostRender(buf.Bytes())
	if err != nil {
		return err
	}

	return ioutil.WriteFile(outputPath, html, 0644)
}

func (b *BuilderV2) generateIndex(tmpl *template.Template) error {
	outputPath := filepath.Join(b.config.OutputDir, "index.html")
	
	data := struct {
		Posts []plugin.Post
	}{
		Posts: b.posts,
	}

	// Pre-render hook
	processed, err := b.pluginManager.PreRender(data)
	if err != nil {
		return err
	}

	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, "index.html", processed); err != nil {
		return err
	}

	// Post-render hook
	html, err := b.pluginManager.PostRender(buf.Bytes())
	if err != nil {
		return err
	}

	return ioutil.WriteFile(outputPath, html, 0644)
}

func (b *BuilderV2) generateSecurityHeaders() error {
	headers := b.pluginManager.GetSecurityHeaders()
	
	var content strings.Builder
	content.WriteString("# Security Headers\n\n")
	
	for key, value := range headers {
		content.WriteString(fmt.Sprintf("%s: %s\n", key, value))
	}
	
	return ioutil.WriteFile(
		filepath.Join(b.config.OutputDir, "_headers"),
		[]byte(content.String()),
		0644,
	)
}

func (b *BuilderV2) copyStatic() error {
	staticDir := "static"
	if _, err := os.Stat(staticDir); os.IsNotExist(err) {
		return nil
	}

	return filepath.Walk(staticDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}

		rel, _ := filepath.Rel(staticDir, path)
		outputPath := filepath.Join(b.config.OutputDir, rel)
		
		os.MkdirAll(filepath.Dir(outputPath), 0755)
		
		input, err := ioutil.ReadFile(path)
		if err != nil {
			return err
		}

		return ioutil.WriteFile(outputPath, input, 0644)
	})
}