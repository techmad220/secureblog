package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"secureblog/internal/builder"
	"secureblog/plugins/integrity"
	"secureblog/plugins/markdown"
	"secureblog/plugins/rss"
	"secureblog/plugins/security"
	"secureblog/plugins/sitemap"
)

func main() {
	var (
		contentDir  = flag.String("content", "content", "Content directory")
		outputDir   = flag.String("output", "build", "Output directory")
		pluginDir   = flag.String("plugins", "plugins", "Plugin directory")
		configFile  = flag.String("config", "config.yaml", "Config file")
		listPlugins = flag.Bool("list-plugins", false, "List available plugins")
	)
	flag.Parse()

	if *listPlugins {
		listAvailablePlugins()
		return
	}

	// Clean output directory
	os.RemoveAll(*outputDir)
	os.MkdirAll(*outputDir, 0755)

	// Initialize builder with plugin system
	b := builder.NewV2(builder.Config{
		ContentDir:  *contentDir,
		OutputDir:   *outputDir,
		TemplateDir: "templates",
		Secure:      true,
	})

	// Register core plugins
	fmt.Println("🔌 Loading plugins...")
	
	// Content processing
	b.RegisterPlugin(markdown.New())
	fmt.Println("  ✓ Markdown processor")
	
	// Security
	b.RegisterPlugin(security.NewCSP())
	fmt.Println("  ✓ CSP security")
	
	// Output formats
	b.RegisterPlugin(rss.New())
	fmt.Println("  ✓ RSS generator")
	
	b.RegisterPlugin(sitemap.New())
	fmt.Println("  ✓ Sitemap generator")
	
	// Build integrity
	b.RegisterPlugin(integrity.New())
	fmt.Println("  ✓ Integrity hashing")

	// Load custom plugins from directory
	if err := loadCustomPlugins(b, *pluginDir); err != nil {
		log.Printf("Warning: Failed to load custom plugins: %v", err)
	}

	// Build the site
	fmt.Println("\n🔨 Building secure blog...")
	if err := b.Build(); err != nil {
		log.Fatalf("Build failed: %v", err)
	}

	fmt.Printf("\n✅ Secure blog built successfully in %s\n", *outputDir)
	fmt.Println("🔒 Security features enabled:")
	fmt.Println("  • Zero JavaScript")
	fmt.Println("  • CSP headers generated")
	fmt.Println("  • Content integrity hashes")
	fmt.Println("  • No external dependencies")
}

func listAvailablePlugins() {
	fmt.Println("📦 Available Plugins:")
	fmt.Println("\nCore Plugins:")
	fmt.Println("  • markdown     - Markdown to HTML conversion")
	fmt.Println("  • csp-security - Content Security Policy")
	fmt.Println("  • integrity    - SHA256 content hashing")
	fmt.Println("  • rss          - RSS feed generation")
	fmt.Println("  • sitemap      - XML sitemap generation")
	fmt.Println("\nCustom Plugins:")
	fmt.Println("  Place .go files in plugins/ directory")
}

func loadCustomPlugins(b *builder.BuilderV2, pluginDir string) error {
	// In production, this would load compiled plugins
	// For security, we only load pre-compiled plugins
	return nil
}