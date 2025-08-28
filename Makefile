.PHONY: build clean verify deploy serve dev

# Build the blog
build:
	@echo "🔨 Building blog generator..."
	@go build -ldflags="-s -w" -trimpath -o secureblog cmd/main.go
	@echo "📝 Generating static site..."
	@./secureblog -content=content -output=build -sign=true
	@echo "✅ Build complete"

# Clean build artifacts
clean:
	@echo "🧹 Cleaning..."
	@rm -rf build deploy.tar.gz deploy.tar.gz.sha256 secureblog
	@echo "✅ Clean complete"

# Verify build integrity
verify:
	@echo "🔍 Verifying build integrity..."
	@./secureblog -verify=true -output=build
	@echo "✅ Integrity verified"

# Deploy locally for testing
serve: build
	@echo "🚀 Starting local server on http://localhost:8080"
	@echo "⚠️  This is for testing only. In production, use Nginx/Apache with proper security headers"
	@cd build && python3 -m http.server 8080

# Development mode with auto-rebuild
dev:
	@echo "👀 Watching for changes..."
	@while true; do \
		inotifywait -r -e modify,create,delete content/ templates/ 2>/dev/null || sleep 2; \
		make build; \
	done

# Security audit
audit:
	@echo "🔒 Running security audit..."
	@go mod verify
	@go vet ./...
	@staticcheck ./... 2>/dev/null || echo "⚠️  staticcheck not installed"
	@gosec ./... 2>/dev/null || echo "⚠️  gosec not installed"
	@echo "✅ Security audit complete"

# Show security headers
headers:
	@echo "📋 Security headers for your web server:"
	@echo "----------------------------------------"
	@cat build/_headers 2>/dev/null || echo "Run 'make build' first"

# Initialize new blog
init:
	@echo "🎯 Initializing secure blog..."
	@mkdir -p content/posts templates static/css build
	@go mod tidy
	@echo "✅ Blog initialized. Run 'make build' to generate your site"