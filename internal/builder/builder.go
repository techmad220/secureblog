package builder

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"html/template"
	"io/ioutil"
	"os"
	"path/filepath"
	"secureblog/internal/security"
	"sort"
	"strings"
	"time"

	"github.com/russross/blackfriday/v2"
)

type Config struct {
	ContentDir  string
	OutputDir   string
	TemplateDir string
	Secure      bool
}

type Builder struct {
	config Config
	posts  []Post
}

type Post struct {
	Title       string
	Content     template.HTML
	Date        time.Time
	Slug        string
	Hash        string
	ContentHash string
}

func New(config Config) *Builder {
	return &Builder{config: config}
}

func (b *Builder) Build() error {
	// Parse templates
	tmpl, err := b.parseTemplates()
	if err != nil {
		return fmt.Errorf("parsing templates: %w", err)
	}

	// Load and parse posts
	if err := b.loadPosts(); err != nil {
		return fmt.Errorf("loading posts: %w", err)
	}

	// Generate individual post pages
	for _, post := range b.posts {
		if err := b.generatePost(tmpl, post); err != nil {
			return fmt.Errorf("generating post %s: %w", post.Slug, err)
		}
	}

	// Generate index page
	if err := b.generateIndex(tmpl); err != nil {
		return fmt.Errorf("generating index: %w", err)
	}

	// Generate RSS feed
	if err := b.generateRSS(); err != nil {
		return fmt.Errorf("generating RSS: %w", err)
	}

	// Copy static files with integrity checks
	if err := b.copyStatic(); err != nil {
		return fmt.Errorf("copying static files: %w", err)
	}

	return nil
}

func (b *Builder) parseTemplates() (*template.Template, error) {
	// Use strict template parsing with security functions
	tmpl := template.New("").Funcs(template.FuncMap{
		"sanitize": security.SanitizeHTML,
		"escape":   security.EscapeHTML,
	})

	return tmpl.ParseGlob(filepath.Join(b.config.TemplateDir, "*.html"))
}

func (b *Builder) loadPosts() error {
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

		// Parse markdown with strict settings
		html := blackfriday.Run(content,
			blackfriday.WithNoExtensions(),
			blackfriday.WithRenderer(blackfriday.NewHTMLRenderer(
				blackfriday.HTMLRendererParameters{
					Flags: blackfriday.NoreferrerLinks |
						blackfriday.NoFollowLinks |
						blackfriday.HrefTargetBlank,
				})))

		// Calculate content hash for integrity
		h := sha256.Sum256(html)
		contentHash := hex.EncodeToString(h[:])

		post := Post{
			Title:       strings.TrimSuffix(file.Name(), ".md"),
			Content:     template.HTML(html),
			Date:        file.ModTime(),
			Slug:        strings.TrimSuffix(file.Name(), ".md"),
			ContentHash: contentHash,
		}

		b.posts = append(b.posts, post)
	}

	// Sort posts by date (newest first)
	sort.Slice(b.posts, func(i, j int) bool {
		return b.posts[i].Date.After(b.posts[j].Date)
	})

	return nil
}

func (b *Builder) generatePost(tmpl *template.Template, post Post) error {
	outputPath := filepath.Join(b.config.OutputDir, post.Slug+".html")
	
	var buf bytes.Buffer
	data := struct {
		Post      Post
		CSPNonce  string
		Integrity string
		NoJS      bool
	}{
		Post:     post,
		CSPNonce: security.GenerateNonce(),
		NoJS:     true,
	}

	if err := tmpl.ExecuteTemplate(&buf, "post.html", data); err != nil {
		return err
	}

	return ioutil.WriteFile(outputPath, buf.Bytes(), 0644)
}

func (b *Builder) generateIndex(tmpl *template.Template) error {
	outputPath := filepath.Join(b.config.OutputDir, "index.html")
	
	var buf bytes.Buffer
	data := struct {
		Posts    []Post
		CSPNonce string
		NoJS     bool
	}{
		Posts:    b.posts,
		CSPNonce: security.GenerateNonce(),
		NoJS:     true,
	}

	if err := tmpl.ExecuteTemplate(&buf, "index.html", data); err != nil {
		return err
	}

	return ioutil.WriteFile(outputPath, buf.Bytes(), 0644)
}

func (b *Builder) generateRSS() error {
	outputPath := filepath.Join(b.config.OutputDir, "feed.xml")
	
	rss := `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
<title>Secure Blog</title>
<description>A security-focused blog</description>
<link>/</link>
`
	for _, post := range b.posts {
		rss += fmt.Sprintf(`<item>
<title>%s</title>
<link>/%s.html</link>
<pubDate>%s</pubDate>
<description><![CDATA[%s]]></description>
</item>
`, security.EscapeXML(post.Title), post.Slug, post.Date.Format(time.RFC1123Z), post.Content)
	}
	
	rss += `</channel></rss>`
	
	return ioutil.WriteFile(outputPath, []byte(rss), 0644)
}

func (b *Builder) copyStatic() error {
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