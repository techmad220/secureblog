package rss

import (
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"path/filepath"
	"secureblog/internal/plugin"
	"time"
)

// RSSPlugin generates RSS feeds
type RSSPlugin struct {
	config map[string]interface{}
}

type RSS struct {
	XMLName xml.Name `xml:"rss"`
	Version string   `xml:"version,attr"`
	Channel Channel  `xml:"channel"`
}

type Channel struct {
	Title       string `xml:"title"`
	Link        string `xml:"link"`
	Description string `xml:"description"`
	Items       []Item `xml:"item"`
}

type Item struct {
	Title       string `xml:"title"`
	Link        string `xml:"link"`
	Description string `xml:"description"`
	PubDate     string `xml:"pubDate"`
	GUID        string `xml:"guid"`
}

func New() *RSSPlugin {
	return &RSSPlugin{}
}

func (p *RSSPlugin) Name() string {
	return "rss-generator"
}

func (p *RSSPlugin) Version() string {
	return "1.0.0"
}

func (p *RSSPlugin) Init(config map[string]interface{}) error {
	p.config = config
	return nil
}

func (p *RSSPlugin) Priority() int {
	return 50
}

func (p *RSSPlugin) Generate(posts []plugin.Post, outputDir string) error {
	// Get site config
	siteTitle := "Secure Blog"
	siteURL := "/"
	siteDesc := "A security-focused blog"
	
	if title, ok := p.config["title"].(string); ok {
		siteTitle = title
	}
	if url, ok := p.config["url"].(string); ok {
		siteURL = url
	}
	if desc, ok := p.config["description"].(string); ok {
		siteDesc = desc
	}

	// Build RSS feed
	rss := RSS{
		Version: "2.0",
		Channel: Channel{
			Title:       siteTitle,
			Link:        siteURL,
			Description: siteDesc,
			Items:       []Item{},
		},
	}

	for _, post := range posts {
		item := Item{
			Title:       post.Title,
			Link:        fmt.Sprintf("%s/%s.html", siteURL, post.Slug),
			Description: string(post.Content),
			PubDate:     post.Date,
			GUID:        fmt.Sprintf("%s/%s", siteURL, post.Slug),
		}
		rss.Channel.Items = append(rss.Channel.Items, item)
	}

	// Marshal to XML
	output, err := xml.MarshalIndent(rss, "", "  ")
	if err != nil {
		return err
	}

	// Write RSS file
	rssPath := filepath.Join(outputDir, "feed.xml")
	xmlContent := xml.Header + string(output)
	
	return ioutil.WriteFile(rssPath, []byte(xmlContent), 0644)
}

var _ plugin.OutputPlugin = (*RSSPlugin)(nil)