#!/usr/bin/env bash
# start-admin.sh - Launch SecureBlog Admin Interface
set -euo pipefail

echo "🔒 SecureBlog Admin Server"
echo "========================="
echo "WordPress Easy, Fort Knox Secure"
echo ""

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "❌ Go is not installed. Please install Go 1.23+ first."
    echo "   https://golang.org/dl/"
    exit 1
fi

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
if [[ "$(printf '%s\n' "1.21" "$GO_VERSION" | sort -V | head -n1)" != "1.21" ]]; then
    echo "⚠️  Go version $GO_VERSION detected. Recommended: Go 1.23+"
fi

# Create necessary directories
echo "📁 Setting up directories..."
mkdir -p content/posts
mkdir -p content/images
mkdir -p ui/static
mkdir -p templates
mkdir -p dist

# Check if admin password is set
if [ -z "${ADMIN_PASSWORD:-}" ]; then
    echo "⚠️  ADMIN_PASSWORD not set. Using default: secure123"
    echo "   Set environment variable for production:"
    echo "   export ADMIN_PASSWORD=your-secure-password"
    echo ""
fi

# Install dependencies if needed
if [ ! -f "go.mod" ]; then
    echo "📦 Initializing Go module..."
    go mod init secureblog
fi

# Add required dependencies
echo "📦 Installing dependencies..."
go get github.com/gorilla/mux
go get github.com/gorilla/securecookie

# Build admin server
echo "🔨 Building admin server..."
go build -o admin-server ./cmd/admin-server/

# Check port availability
if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "❌ Port 3000 is already in use. Please free the port or modify the server."
    exit 1
fi

echo "✅ Setup complete!"
echo ""
echo "🚀 Starting admin server..."
echo ""
echo "📍 Admin Interface: http://localhost:3000"
echo "👤 Username: admin"
echo "🔑 Password: ${ADMIN_PASSWORD:-secure123}"
echo ""
echo "🔒 Security Features Active:"
echo "   • Zero JavaScript deployment"
echo "   • Automatic content sanitization"  
echo "   • Secure session management"
echo "   • Input validation & filtering"
echo "   • Path traversal protection"
echo "   • File upload restrictions"
echo ""
echo "🎯 Quick Actions:"
echo "   • Write posts with live preview"
echo "   • Upload images with drag & drop"
echo "   • One-click secure deployment"
echo "   • Real-time security monitoring"
echo "   • Visual theme editing"
echo ""
echo "Press Ctrl+C to stop the server"
echo "================================="

# Set admin password in environment if not set
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-secure123}"

# Start the server
./admin-server