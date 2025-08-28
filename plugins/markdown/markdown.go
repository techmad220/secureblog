package markdown

import (
	"secureblog/internal/plugin"
	"github.com/russross/blackfriday/v2"
)

// MarkdownPlugin converts markdown to HTML
type MarkdownPlugin struct {
	config map[string]interface{}
}

func New() *MarkdownPlugin {
	return &MarkdownPlugin{}
}

func (p *MarkdownPlugin) Name() string {
	return "markdown"
}

func (p *MarkdownPlugin) Version() string {
	return "1.0.0"
}

func (p *MarkdownPlugin) Init(config map[string]interface{}) error {
	p.config = config
	return nil
}

func (p *MarkdownPlugin) Priority() int {
	return 10 // Run early in the pipeline
}

func (p *MarkdownPlugin) ProcessContent(content []byte, metadata map[string]interface{}) ([]byte, error) {
	// Strict markdown parsing for security
	html := blackfriday.Run(content,
		blackfriday.WithNoExtensions(),
		blackfriday.WithRenderer(blackfriday.NewHTMLRenderer(
			blackfriday.HTMLRendererParameters{
				Flags: blackfriday.NoreferrerLinks |
					blackfriday.NoFollowLinks |
					blackfriday.HrefTargetBlank |
					blackfriday.NorfollowLinks,
			})))
	
	return html, nil
}

// Ensure it implements ContentPlugin
var _ plugin.ContentPlugin = (*MarkdownPlugin)(nil)