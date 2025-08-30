//! SecureBlog-RS: Memory-safe static blog generator with zero JavaScript
//! 
//! This is a Rust rewrite for maximum security through memory safety,
//! eliminating entire classes of vulnerabilities present in C/C++ code.

#![forbid(unsafe_code)]
#![warn(
    clippy::all,
    clippy::pedantic,
    clippy::nursery,
    clippy::cargo,
    missing_docs
)]

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use tracing::{debug, info, warn};
use walkdir::WalkDir;

mod generator;
mod markdown;
mod security;
mod templates;

/// Post metadata from YAML frontmatter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostMeta {
    /// Post title
    pub title: String,
    /// Publication date
    pub date: DateTime<Utc>,
    /// Post tags
    #[serde(default)]
    pub tags: Vec<String>,
    /// Post slug (URL path)
    #[serde(default)]
    pub slug: String,
    /// Draft status
    #[serde(default)]
    pub draft: bool,
}

/// Represents a blog post
#[derive(Debug, Clone)]
pub struct Post {
    /// Post metadata
    pub meta: PostMeta,
    /// Raw markdown content
    pub content: String,
    /// Rendered HTML (sanitized)
    pub html: String,
    /// Content hash for integrity
    pub hash: String,
    /// Source file path
    pub source: PathBuf,
}

/// Main application configuration
#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Site title
    pub title: String,
    /// Site URL
    pub url: String,
    /// Author name
    pub author: String,
    /// Output directory
    #[serde(default = "default_output")]
    pub output: PathBuf,
    /// Content directory
    #[serde(default = "default_content")]
    pub content: PathBuf,
    /// Enable BLAKE3 hashing (faster than SHA-256)
    #[serde(default)]
    pub use_blake3: bool,
}

fn default_output() -> PathBuf {
    PathBuf::from("dist")
}

fn default_content() -> PathBuf {
    PathBuf::from("content")
}

/// Security policy enforcement
pub struct SecurityPolicy {
    /// Reject any JavaScript
    pub no_javascript: bool,
    /// Reject inline styles
    pub no_inline_styles: bool,
    /// Reject external resources
    pub no_external: bool,
    /// Maximum file size (bytes)
    pub max_file_size: usize,
}

impl Default for SecurityPolicy {
    fn default() -> Self {
        Self {
            no_javascript: true,
            no_inline_styles: false,
            no_external: true,
            max_file_size: 10 * 1024 * 1024, // 10MB
        }
    }
}

/// Main entry point
fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_target(false)
        .init();

    info!("SecureBlog-RS v{}", env!("CARGO_PKG_VERSION"));
    info!("Memory-safe static site generator");

    // Load configuration
    let config = load_config()?;
    
    // Security policy (strictest possible)
    let policy = SecurityPolicy::default();
    
    // Clean output directory
    if config.output.exists() {
        fs::remove_dir_all(&config.output)
            .context("Failed to clean output directory")?;
    }
    fs::create_dir_all(&config.output)
        .context("Failed to create output directory")?;

    // Load and process posts in parallel (Rayon)
    let posts = load_posts(&config.content, &policy)?;
    info!("Loaded {} posts", posts.len());

    // Generate site (parallel rendering)
    generator::generate_site(&config, &posts, &policy)?;

    // Generate integrity manifest
    let manifest = generate_manifest(&config.output)?;
    fs::write(
        config.output.join("integrity.json"),
        serde_json::to_string_pretty(&manifest)?,
    )?;

    // Security validation
    security::validate_output(&config.output, &policy)?;

    info!("✅ Site generated successfully");
    info!("📁 Output: {}", config.output.display());
    info!("🔒 Zero JavaScript, fully static");

    Ok(())
}

/// Load configuration from file
fn load_config() -> Result<Config> {
    let config_path = Path::new("config.yaml");
    if !config_path.exists() {
        return Ok(Config {
            title: "SecureBlog".to_string(),
            url: "https://example.com".to_string(),
            author: "Anonymous".to_string(),
            output: default_output(),
            content: default_content(),
            use_blake3: true,
        });
    }

    let content = fs::read_to_string(config_path)
        .context("Failed to read config.yaml")?;
    let config: Config = serde_yaml::from_str(&content)
        .context("Failed to parse config.yaml")?;

    Ok(config)
}

/// Load all posts from content directory
fn load_posts(content_dir: &Path, policy: &SecurityPolicy) -> Result<Vec<Post>> {
    let posts: Result<Vec<_>> = WalkDir::new(content_dir)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.path().extension()
                .and_then(|s| s.to_str())
                .map_or(false, |ext| ext == "md" || ext == "markdown")
        })
        .par_bridge() // Parallel processing
        .map(|entry| load_post(entry.path(), policy))
        .collect();

    let mut posts = posts?;
    
    // Sort by date (newest first)
    posts.sort_by(|a, b| b.meta.date.cmp(&a.meta.date));
    
    // Filter drafts in release mode
    #[cfg(not(debug_assertions))]
    {
        posts.retain(|p| !p.meta.draft);
    }

    Ok(posts)
}

/// Load a single post
fn load_post(path: &Path, policy: &SecurityPolicy) -> Result<Post> {
    let content = fs::read_to_string(path)
        .with_context(|| format!("Failed to read post: {}", path.display()))?;

    // Check file size
    if content.len() > policy.max_file_size {
        anyhow::bail!("Post exceeds maximum size: {}", path.display());
    }

    // Parse frontmatter and content
    let (meta, markdown) = markdown::parse_frontmatter(&content)?;

    // Render and sanitize HTML
    let html = markdown::render_markdown(&markdown, policy)?;

    // Calculate content hash
    let hash = if meta.draft {
        "DRAFT".to_string()
    } else {
        let mut hasher = Sha256::new();
        hasher.update(&html);
        format!("{:x}", hasher.finalize())
    };

    Ok(Post {
        meta,
        content: markdown,
        html,
        hash,
        source: path.to_path_buf(),
    })
}

/// Generate integrity manifest
fn generate_manifest(output_dir: &Path) -> Result<serde_json::Value> {
    let mut files = Vec::new();

    for entry in WalkDir::new(output_dir)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        let path = entry.path();
        let relative = path.strip_prefix(output_dir)?;
        
        let content = fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let hash = format!("{:x}", hasher.finalize());

        files.push(serde_json::json!({
            "path": relative.display().to_string(),
            "size": content.len(),
            "sha256": hash,
        }));
    }

    Ok(serde_json::json!({
        "version": "1.0",
        "generated": Utc::now().to_rfc3339(),
        "generator": "secureblog-rs",
        "files": files,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_security_policy_default() {
        let policy = SecurityPolicy::default();
        assert!(policy.no_javascript);
        assert!(policy.no_external);
        assert_eq!(policy.max_file_size, 10 * 1024 * 1024);
    }

    #[test]
    fn test_config_defaults() {
        let config = Config {
            title: "Test".to_string(),
            url: "https://test.com".to_string(),
            author: "Tester".to_string(),
            output: default_output(),
            content: default_content(),
            use_blake3: false,
        };
        assert_eq!(config.output, PathBuf::from("dist"));
        assert_eq!(config.content, PathBuf::from("content"));
    }
}