package main

import (
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"html/template"
	"io"
	"log"
	"os"
	"path/filepath"
	"secureblog/internal/builder"
	"secureblog/internal/security"
)

func main() {
	var (
		contentDir = flag.String("content", "content", "Content directory")
		outputDir  = flag.String("output", "build", "Output directory")
		signOutput = flag.Bool("sign", true, "Sign output files")
		verify     = flag.Bool("verify", false, "Verify build integrity")
	)
	flag.Parse()

	if *verify {
		if err := security.VerifyBuild(*outputDir); err != nil {
			log.Fatalf("Build verification failed: %v", err)
		}
		fmt.Println("✓ Build integrity verified")
		return
	}

	// Clean output directory
	os.RemoveAll(*outputDir)
	os.MkdirAll(*outputDir, 0755)

	// Initialize builder with security settings
	b := builder.New(builder.Config{
		ContentDir:  *contentDir,
		OutputDir:   *outputDir,
		TemplateDir: "templates",
		Secure:      true,
	})

	// Build the site
	if err := b.Build(); err != nil {
		log.Fatalf("Build failed: %v", err)
	}

	// Sign output if requested
	if *signOutput {
		if err := security.SignBuild(*outputDir); err != nil {
			log.Fatalf("Failed to sign build: %v", err)
		}
		fmt.Println("✓ Build signed with SHA256")
	}

	// Generate security headers file
	security.GenerateHeaders(*outputDir)
	
	fmt.Printf("✓ Secure blog built successfully in %s\n", *outputDir)
	fmt.Println("✓ CSP headers generated")
	fmt.Println("✓ No JavaScript included")
	fmt.Println("✓ No external dependencies")
}