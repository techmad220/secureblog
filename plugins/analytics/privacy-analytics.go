package analytics

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"time"
)

// Plugin provides privacy-preserving analytics
type Plugin struct {
	enabled bool
	config  Config
	logger  *log.Logger
}

// Config holds analytics configuration
type Config struct {
	Enabled           bool   `json:"enabled"`
	LogPath          string `json:"log_path"`
	HashSalt         string `json:"hash_salt"`
	RetentionDays    int    `json:"retention_days"`
	AnonymizeIP      bool   `json:"anonymize_ip"`
	ExcludeUserAgent bool   `json:"exclude_user_agent"`
	ExcludeReferer   bool   `json:"exclude_referer"`
}

// NewPlugin creates analytics plugin
func NewPlugin(config Config, logger *log.Logger) *Plugin {
	return &Plugin{
		enabled: config.Enabled,
		config:  config,
		logger:  logger,
	}
}

// LogRequest logs request with privacy preservation
func (p *Plugin) LogRequest(r *http.Request) {
	if !p.enabled {
		return
	}
	
	entry := p.createLogEntry(r)
	p.logger.Println(entry)
}

// createLogEntry creates privacy-preserving log entry
func (p *Plugin) createLogEntry(r *http.Request) string {
	var parts []string
	
	// Timestamp
	parts = append(parts, time.Now().UTC().Format(time.RFC3339))
	
	// Anonymized IP
	ip := p.anonymizeIP(r.RemoteAddr)
	parts = append(parts, ip)
	
	// Method and path (no query strings with potential PII)
	parts = append(parts, r.Method)
	parts = append(parts, r.URL.Path)
	
	// Status placeholder (filled by response writer)
	parts = append(parts, "-")
	
	// Response size placeholder
	parts = append(parts, "-")
	
	// Anonymized user agent
	if !p.config.ExcludeUserAgent {
		ua := p.anonymizeUserAgent(r.UserAgent())
		parts = append(parts, ua)
	}
	
	// Anonymized referer
	if !p.config.ExcludeReferer {
		ref := p.anonymizeReferer(r.Referer())
		parts = append(parts, ref)
	}
	
	return strings.Join(parts, " | ")
}

// anonymizeIP removes last octet for IPv4 or last 80 bits for IPv6
func (p *Plugin) anonymizeIP(addr string) string {
	if !p.config.AnonymizeIP {
		return addr
	}
	
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
	}
	
	ip := net.ParseIP(host)
	if ip == nil {
		return "unknown"
	}
	
	if ip.To4() != nil {
		// IPv4: zero last octet
		ip = ip.To4()
		ip[3] = 0
	} else {
		// IPv6: zero last 80 bits
		for i := 6; i < 16; i++ {
			ip[i] = 0
		}
	}
	
	return ip.String()
}

// anonymizeUserAgent keeps only browser and OS info
func (p *Plugin) anonymizeUserAgent(ua string) string {
	if ua == "" {
		return "-"
	}
	
	// Simple categorization to avoid fingerprinting
	lower := strings.ToLower(ua)
	
	browser := "other"
	if strings.Contains(lower, "firefox") {
		browser = "firefox"
	} else if strings.Contains(lower, "chrome") {
		browser = "chrome"
	} else if strings.Contains(lower, "safari") {
		browser = "safari"
	} else if strings.Contains(lower, "edge") {
		browser = "edge"
	}
	
	os := "other"
	if strings.Contains(lower, "windows") {
		os = "windows"
	} else if strings.Contains(lower, "mac") {
		os = "mac"
	} else if strings.Contains(lower, "linux") {
		os = "linux"
	} else if strings.Contains(lower, "android") {
		os = "android"
	} else if strings.Contains(lower, "ios") || strings.Contains(lower, "iphone") {
		os = "ios"
	}
	
	return fmt.Sprintf("%s/%s", browser, os)
}

// anonymizeReferer removes query strings and fragments
func (p *Plugin) anonymizeReferer(ref string) string {
	if ref == "" {
		return "-"
	}
	
	// Remove everything after ? or #
	if idx := strings.IndexAny(ref, "?#"); idx != -1 {
		ref = ref[:idx]
	}
	
	// Only keep domain for external referers
	if !strings.Contains(ref, "secureblog.com") {
		if idx := strings.Index(ref, "://"); idx != -1 {
			afterProto := ref[idx+3:]
			if slashIdx := strings.Index(afterProto, "/"); slashIdx != -1 {
				ref = ref[:idx+3+slashIdx]
			}
		}
	}
	
	return ref
}

// HashVisitor creates hash of visitor for unique counting without storing PII
func (p *Plugin) HashVisitor(r *http.Request) string {
	// Combine IP (truncated) + User-Agent (simplified) + Date for daily uniques
	data := fmt.Sprintf("%s|%s|%s|%s",
		p.anonymizeIP(r.RemoteAddr),
		p.anonymizeUserAgent(r.UserAgent()),
		time.Now().Format("2006-01-02"),
		p.config.HashSalt,
	)
	
	hash := sha256.Sum256([]byte(data))
	return hex.EncodeToString(hash[:16]) // Use first 16 bytes
}

// ResponseWriter wraps http.ResponseWriter to capture status and size
type ResponseWriter struct {
	http.ResponseWriter
	statusCode int
	size       int
}

func (rw *ResponseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *ResponseWriter) Write(b []byte) (int, error) {
	size, err := rw.ResponseWriter.Write(b)
	rw.size += size
	return size, err
}

// WrapHandler wraps HTTP handler with analytics
func (p *Plugin) WrapHandler(next http.Handler) http.Handler {
	if !p.enabled {
		return next
	}
	
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Skip analytics for certain paths
		if strings.HasPrefix(r.URL.Path, "/health") ||
		   strings.HasPrefix(r.URL.Path, "/metrics") {
			next.ServeHTTP(w, r)
			return
		}
		
		// Wrap response writer
		rw := &ResponseWriter{ResponseWriter: w, statusCode: 200}
		
		// Log request
		start := time.Now()
		next.ServeHTTP(rw, r)
		duration := time.Since(start)
		
		// Log with response info
		p.logRequestComplete(r, rw.statusCode, rw.size, duration)
	})
}

// logRequestComplete logs completed request
func (p *Plugin) logRequestComplete(r *http.Request, status, size int, duration time.Duration) {
	entry := fmt.Sprintf("%s | %s | %s | %s | %d | %d | %dms",
		time.Now().UTC().Format(time.RFC3339),
		p.anonymizeIP(r.RemoteAddr),
		r.Method,
		r.URL.Path,
		status,
		size,
		duration.Milliseconds(),
	)
	
	if !p.config.ExcludeUserAgent {
		entry += " | " + p.anonymizeUserAgent(r.UserAgent())
	}
	
	if !p.config.ExcludeReferer {
		entry += " | " + p.anonymizeReferer(r.Referer())
	}
	
	// Add visitor hash for unique counting
	entry += " | " + p.HashVisitor(r)
	
	p.logger.Println(entry)
}