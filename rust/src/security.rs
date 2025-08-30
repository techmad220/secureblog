//! Security validation and sanitization module

use anyhow::{Context, Result};
use once_cell::sync::Lazy;
use regex::Regex;
use std::path::Path;
use tracing::{error, warn};
use walkdir::WalkDir;

use crate::SecurityPolicy;

/// Regex patterns for detecting JavaScript and other security issues
static JS_PATTERNS: Lazy<Vec<Regex>> = Lazy::new(|| {
    vec![
        Regex::new(r"<script\b").unwrap(),
        Regex::new(r"javascript:").unwrap(),
        Regex::new(r"on\w+\s*=").unwrap(), // onclick, onload, etc.
        Regex::new(r"<iframe\b").unwrap(),
        Regex::new(r"<object\b").unwrap(),
        Regex::new(r"<embed\b").unwrap(),
        Regex::new(r"<applet\b").unwrap(),
        Regex::new(r"eval\s*\(").unwrap(),
        Regex::new(r"Function\s*\(").unwrap(),
        Regex::new(r"setTimeout\s*\(").unwrap(),
        Regex::new(r"setInterval\s*\(").unwrap(),
        Regex::new(r"\.innerHTML\s*=").unwrap(),
        Regex::new(r"document\.write").unwrap(),
        Regex::new(r"window\.location").unwrap(),
    ]
});

/// Validate that output directory contains no JavaScript or security issues
pub fn validate_output(output_dir: &Path, policy: &SecurityPolicy) -> Result<()> {
    let mut violations = Vec::new();

    for entry in WalkDir::new(output_dir)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        let path = entry.path();
        
        // Only check HTML/CSS/JS files
        let ext = path.extension().and_then(|s| s.to_str());
        match ext {
            Some("html") | Some("htm") => {
                validate_html_file(path, policy, &mut violations)?;
            }
            Some("css") => {
                validate_css_file(path, policy, &mut violations)?;
            }
            Some("js") if policy.no_javascript => {
                violations.push(format!("JavaScript file found: {}", path.display()));
            }
            _ => {}
        }
    }

    if !violations.is_empty() {
        error!("Security violations detected:");
        for violation in &violations {
            error!("  - {}", violation);
        }
        anyhow::bail!("Security validation failed with {} violations", violations.len());
    }

    Ok(())
}

/// Validate HTML file for security issues
fn validate_html_file(path: &Path, policy: &SecurityPolicy, violations: &mut Vec<String>) -> Result<()> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read HTML file: {}", path.display()))?;

    // Check for JavaScript patterns
    if policy.no_javascript {
        for pattern in JS_PATTERNS.iter() {
            if pattern.is_match(&content) {
                violations.push(format!(
                    "JavaScript pattern '{}' found in {}",
                    pattern.as_str(),
                    path.display()
                ));
            }
        }
    }

    // Check for inline styles
    if policy.no_inline_styles {
        let style_regex = Regex::new(r#"style\s*=\s*["'][^"']*["']"#).unwrap();
        if style_regex.is_match(&content) {
            violations.push(format!("Inline styles found in {}", path.display()));
        }
    }

    // Check for external resources
    if policy.no_external {
        let external_regex = Regex::new(r#"(src|href)\s*=\s*["'](https?://[^"']+)["']"#).unwrap();
        for cap in external_regex.captures_iter(&content) {
            let url = &cap[2];
            // Allow same-origin resources
            if !url.starts_with('/') && !url.starts_with('#') {
                violations.push(format!("External resource '{}' in {}", url, path.display()));
            }
        }
    }

    Ok(())
}

/// Validate CSS file for security issues
fn validate_css_file(path: &Path, policy: &SecurityPolicy, violations: &mut Vec<String>) -> Result<()> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read CSS file: {}", path.display()))?;

    // Check for JavaScript in CSS
    if policy.no_javascript {
        let js_in_css = Regex::new(r"javascript:|expression\s*\(|behavior\s*:").unwrap();
        if js_in_css.is_match(&content) {
            violations.push(format!("JavaScript in CSS found in {}", path.display()));
        }
    }

    // Check for external imports
    if policy.no_external {
        let import_regex = Regex::new(r"@import\s+[\"']?(https?://[^\"']+)").unwrap();
        for cap in import_regex.captures_iter(&content) {
            let url = &cap[1];
            violations.push(format!("External CSS import '{}' in {}", url, path.display()));
        }
    }

    Ok(())
}

/// Sanitize HTML content using ammonia
pub fn sanitize_html(html: &str, policy: &SecurityPolicy) -> String {
    let mut builder = ammonia::Builder::default();

    // Configure allowed tags (no script, iframe, etc.)
    let allowed_tags: std::collections::HashSet<&str> = [
        "p", "br", "strong", "em", "u", "i", "b",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "dl", "dt", "dd",
        "a", "img", "blockquote", "code", "pre",
        "table", "thead", "tbody", "tr", "th", "td",
        "hr", "div", "span", "article", "section",
        "header", "footer", "nav", "aside", "main",
    ].iter().copied().collect();

    builder.tags(allowed_tags);

    // Remove all event handlers
    builder.rm_tag_attributes("*", &[
        "onclick", "onload", "onerror", "onmouseover", "onmouseout",
        "onkeydown", "onkeyup", "onfocus", "onblur", "onchange",
        "onsubmit", "ondblclick", "onmouseenter", "onmouseleave",
    ]);

    // Disallow javascript: URLs
    builder.url_schemes(std::collections::HashSet::from([
        "http", "https", "mailto", "#",
    ]));

    // Remove style attributes if policy requires
    if policy.no_inline_styles {
        builder.rm_tag_attributes("*", &["style"]);
    }

    builder.clean(html).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_html_removes_script() {
        let policy = SecurityPolicy::default();
        let dirty = r#"<p>Hello</p><script>alert('xss')</script>"#;
        let clean = sanitize_html(dirty, &policy);
        assert!(!clean.contains("script"));
        assert!(clean.contains("Hello"));
    }

    #[test]
    fn test_sanitize_html_removes_event_handlers() {
        let policy = SecurityPolicy::default();
        let dirty = r#"<div onclick="alert('xss')">Click me</div>"#;
        let clean = sanitize_html(dirty, &policy);
        assert!(!clean.contains("onclick"));
        assert!(clean.contains("Click me"));
    }

    #[test]
    fn test_sanitize_html_removes_javascript_urls() {
        let policy = SecurityPolicy::default();
        let dirty = r#"<a href="javascript:alert('xss')">Link</a>"#;
        let clean = sanitize_html(dirty, &policy);
        assert!(!clean.contains("javascript:"));
    }

    #[test]
    fn test_js_pattern_detection() {
        let patterns = &*JS_PATTERNS;
        assert!(patterns.iter().any(|p| p.is_match("<script>")));
        assert!(patterns.iter().any(|p| p.is_match("javascript:void(0)")));
        assert!(patterns.iter().any(|p| p.is_match("onclick='alert()'")));
        assert!(patterns.iter().any(|p| p.is_match("<iframe src=")));
    }
}