package analytics

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"path/filepath"
	"secureblog/internal/plugin"
	"time"
)

// CloudflareAnalyticsPlugin fetches stats from Cloudflare API
type CloudflareAnalyticsPlugin struct {
	config  map[string]interface{}
	apiKey  string
	zoneID  string
	enabled bool
}

type AnalyticsData struct {
	PageViews      int64             `json:"pageViews"`
	UniqueVisitors int64             `json:"uniqueVisitors"`
	Bandwidth      int64             `json:"bandwidth"`
	Threats        int64             `json:"threats"`
	CacheHitRate   float64           `json:"cacheHitRate"`
	TopPages       []PageStats       `json:"topPages"`
	Countries      map[string]int64  `json:"countries"`
	LastUpdated    string            `json:"lastUpdated"`
}

type PageStats struct {
	Path  string `json:"path"`
	Views int64  `json:"views"`
}

func NewCloudflare() *CloudflareAnalyticsPlugin {
	return &CloudflareAnalyticsPlugin{}
}

func (p *CloudflareAnalyticsPlugin) Name() string {
	return "cloudflare-analytics"
}

func (p *CloudflareAnalyticsPlugin) Version() string {
	return "1.0.0"
}

func (p *CloudflareAnalyticsPlugin) Init(config map[string]interface{}) error {
	p.config = config
	
	// Get API credentials from config
	if apiKey, ok := config["cf_api_key"].(string); ok && apiKey != "" {
		p.apiKey = apiKey
		p.enabled = true
	}
	
	if zoneID, ok := config["cf_zone_id"].(string); ok {
		p.zoneID = zoneID
	}
	
	return nil
}

func (p *CloudflareAnalyticsPlugin) Priority() int {
	return 80 // Run late in pipeline
}

func (p *CloudflareAnalyticsPlugin) PostBuild(outputDir string) error {
	if !p.enabled {
		// If no API key, create placeholder stats page
		return p.createPlaceholderStats(outputDir)
	}
	
	// Fetch analytics from Cloudflare
	data, err := p.fetchAnalytics()
	if err != nil {
		return fmt.Errorf("fetching analytics: %w", err)
	}
	
	// Generate stats page
	return p.generateStatsPage(data, outputDir)
}

func (p *CloudflareAnalyticsPlugin) fetchAnalytics() (*AnalyticsData, error) {
	// Build API request
	url := fmt.Sprintf("https://api.cloudflare.com/client/v4/zones/%s/analytics/dashboard", p.zoneID)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	
	req.Header.Set("Authorization", "Bearer "+p.apiKey)
	req.Header.Set("Content-Type", "application/json")
	
	// Add date range (last 30 days)
	q := req.URL.Query()
	q.Add("since", time.Now().AddDate(0, 0, -30).Format("2006-01-02"))
	q.Add("until", time.Now().Format("2006-01-02"))
	req.URL.RawQuery = q.Encode()
	
	// Make request
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	
	// Parse response
	var result struct {
		Result struct {
			Totals struct {
				Requests struct {
					All int64 `json:"all"`
				} `json:"requests"`
				PageViews struct {
					All int64 `json:"all"`
				} `json:"pageviews"`
				Uniques struct {
					All int64 `json:"all"`
				} `json:"uniques"`
				Bandwidth struct {
					All int64 `json:"all"`
				} `json:"bandwidth"`
				Threats struct {
					All int64 `json:"all"`
				} `json:"threats"`
			} `json:"totals"`
		} `json:"result"`
	}
	
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	
	// Build analytics data
	data := &AnalyticsData{
		PageViews:      result.Result.Totals.PageViews.All,
		UniqueVisitors: result.Result.Totals.Uniques.All,
		Bandwidth:      result.Result.Totals.Bandwidth.All,
		Threats:        result.Result.Totals.Threats.All,
		LastUpdated:    time.Now().Format("2006-01-02 15:04:05 UTC"),
	}
	
	return data, nil
}

func (p *CloudflareAnalyticsPlugin) generateStatsPage(data *AnalyticsData, outputDir string) error {
	html := fmt.Sprintf(`<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:">
    <title>Blog Statistics - Privacy-First Analytics</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #e0e0e0;
            background: #0a0a0a;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        h1 { color: #00ff41; border-bottom: 2px solid #00ff41; padding-bottom: 10px; margin-bottom: 2em; }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 2em 0;
        }
        .stat-card {
            background: #1a1a1a;
            border: 1px solid #333;
            border-radius: 4px;
            padding: 1.5em;
        }
        .stat-value {
            font-size: 2em;
            color: #00ff41;
            font-weight: bold;
        }
        .stat-label {
            color: #888;
            font-size: 0.9em;
            margin-top: 0.5em;
        }
        .privacy-notice {
            background: #1a1a1a;
            border: 1px solid #00ff41;
            border-radius: 4px;
            padding: 1.5em;
            margin: 2em 0;
        }
        .privacy-notice h2 { color: #00ff41; margin-bottom: 1em; }
        .update-time { color: #666; font-size: 0.8em; margin-top: 2em; }
        a { color: #00ff41; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>📊 Blog Statistics</h1>
    
    <div class="privacy-notice">
        <h2>🔒 Privacy-First Analytics</h2>
        <p>These statistics are collected by Cloudflare at the edge level:</p>
        <ul>
            <li>✅ No JavaScript tracking</li>
            <li>✅ No cookies or fingerprinting</li>
            <li>✅ No personal data collection</li>
            <li>✅ GDPR/CCPA compliant by design</li>
        </ul>
        <p>All metrics are aggregated and anonymous. Your privacy is protected.</p>
    </div>
    
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-value">%s</div>
            <div class="stat-label">Page Views (30 days)</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">%s</div>
            <div class="stat-label">Unique Visitors</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">%s</div>
            <div class="stat-label">Threats Blocked</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">%s</div>
            <div class="stat-label">Bandwidth Served</div>
        </div>
    </div>
    
    <p class="update-time">Last updated: %s</p>
    <p><a href="/">← Back to Blog</a></p>
</body>
</html>`,
		p.formatNumber(data.PageViews),
		p.formatNumber(data.UniqueVisitors),
		p.formatNumber(data.Threats),
		p.formatBytes(data.Bandwidth),
		data.LastUpdated,
	)
	
	return ioutil.WriteFile(filepath.Join(outputDir, "stats.html"), []byte(html), 0644)
}

func (p *CloudflareAnalyticsPlugin) createPlaceholderStats(outputDir string) error {
	html := `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
    <title>Blog Statistics</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #e0e0e0;
            background: #0a0a0a;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        h1 { color: #00ff41; border-bottom: 2px solid #00ff41; padding-bottom: 10px; margin-bottom: 2em; }
        .privacy-notice {
            background: #1a1a1a;
            border: 1px solid #00ff41;
            border-radius: 4px;
            padding: 1.5em;
            margin: 2em 0;
        }
        .privacy-notice h2 { color: #00ff41; margin-bottom: 1em; }
        a { color: #00ff41; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>📊 Blog Statistics</h1>
    
    <div class="privacy-notice">
        <h2>🔒 Privacy-First Analytics</h2>
        <p>This blog uses Cloudflare's edge analytics for privacy-preserving statistics:</p>
        <ul>
            <li>✅ No JavaScript tracking</li>
            <li>✅ No cookies or fingerprinting</li>
            <li>✅ No personal data collection</li>
            <li>✅ GDPR/CCPA compliant by design</li>
        </ul>
        <p>Statistics will appear here once Cloudflare API is configured.</p>
    </div>
    
    <p><a href="/">← Back to Blog</a></p>
</body>
</html>`
	
	return ioutil.WriteFile(filepath.Join(outputDir, "stats.html"), []byte(html), 0644)
}

func (p *CloudflareAnalyticsPlugin) formatNumber(n int64) string {
	if n >= 1000000 {
		return fmt.Sprintf("%.1fM", float64(n)/1000000)
	} else if n >= 1000 {
		return fmt.Sprintf("%.1fK", float64(n)/1000)
	}
	return fmt.Sprintf("%d", n)
}

func (p *CloudflareAnalyticsPlugin) formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

var _ plugin.BuildPlugin = (*CloudflareAnalyticsPlugin)(nil)