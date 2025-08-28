package sitemap

import (
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"path/filepath"
	"secureblog/internal/plugin"
	"time"
)

// SitemapPlugin generates XML sitemaps
type SitemapPlugin struct {
	config map[string]interface{}
}

type URLSet struct {
	XMLName xml.Name `xml:"urlset"`
	Xmlns   string   `xml:"xmlns,attr"`
	URLs    []URL    `xml:"url"`
}

type URL struct {
	Loc        string `xml:"loc"`
	LastMod    string `xml:"lastmod"`
	ChangeFreq string `xml:"changefreq"`
	Priority   string `xml:"priority"`
}

func New() *SitemapPlugin {
	return &SitemapPlugin{}
}

func (p *SitemapPlugin) Name() string {
	return "sitemap-generator"
}

func (p *SitemapPlugin) Version() string {
	return "1.0.0"
}

func (p *SitemapPlugin) Init(config map[string]interface{}) error {
	p.config = config
	return nil
}

func (p *SitemapPlugin) Priority() int {
	return 51
}

func (p *SitemapPlugin) Generate(posts []plugin.Post, outputDir string) error {
	siteURL := "https://example.com"
	if url, ok := p.config["url"].(string); ok {
		siteURL = url
	}

	urlset := URLSet{
		Xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9",
		URLs:  []URL{},
	}

	// Add homepage
	urlset.URLs = append(urlset.URLs, URL{
		Loc:        siteURL,
		LastMod:    time.Now().Format("2006-01-02"),
		ChangeFreq: "weekly",
		Priority:   "1.0",
	})

	// Add posts
	for _, post := range posts {
		urlset.URLs = append(urlset.URLs, URL{
			Loc:        fmt.Sprintf("%s/%s.html", siteURL, post.Slug),
			LastMod:    post.Date,
			ChangeFreq: "monthly",
			Priority:   "0.8",
		})
	}

	// Marshal to XML
	output, err := xml.MarshalIndent(urlset, "", "  ")
	if err != nil {
		return err
	}

	// Write sitemap
	sitemapPath := filepath.Join(outputDir, "sitemap.xml")
	xmlContent := xml.Header + string(output)
	
	return ioutil.WriteFile(sitemapPath, []byte(xmlContent), 0644)
}

var _ plugin.OutputPlugin = (*SitemapPlugin)(nil)