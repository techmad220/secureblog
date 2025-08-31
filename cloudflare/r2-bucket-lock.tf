# Cloudflare R2 Bucket Lock Configuration
# Enables immutable storage with retention policies for release artifacts
# Prevents deletion/overwriting even with compromised credentials

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# Production artifacts bucket with retention lock
resource "cloudflare_r2_bucket" "secureblog_artifacts" {
  account_id = var.cloudflare_account_id
  name       = "secureblog-artifacts-prod"
  location   = "ENAM" # Eastern North America for compliance
}

# Enable bucket lock with retention policy
resource "cloudflare_r2_bucket_lock" "artifacts_lock" {
  account_id = var.cloudflare_account_id
  bucket     = cloudflare_r2_bucket.secureblog_artifacts.name
  
  # Governance mode - only users with specific IAM permission can bypass
  mode = "GOVERNANCE"
  
  # 90-day retention for production releases
  default_retention {
    mode  = "GOVERNANCE"
    days  = 90
  }
}

# Lifecycle policy for automatic archival
resource "cloudflare_r2_bucket_lifecycle" "artifacts_lifecycle" {
  account_id = var.cloudflare_account_id
  bucket     = cloudflare_r2_bucket.secureblog_artifacts.name
  
  rule {
    id      = "archive-old-releases"
    enabled = true
    
    # Move to cold storage after 30 days
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    
    # Keep releases for 1 year minimum
    expiration {
      days = 365
    }
    
    filter {
      prefix = "releases/"
    }
  }
  
  rule {
    id      = "protect-current"
    enabled = true
    
    # Never expire current/ directory
    filter {
      prefix = "current/"
    }
  }
}

# Object lock configuration for individual objects
resource "cloudflare_r2_bucket_object_lock" "release_lock" {
  account_id = var.cloudflare_account_id
  bucket     = cloudflare_r2_bucket.secureblog_artifacts.name
  
  # Legal hold for critical releases
  legal_hold = true
  
  # Compliance mode for regulatory requirements
  retention {
    mode              = "COMPLIANCE"
    retain_until_date = "2026-12-31T23:59:59Z"
  }
}

# Versioning for audit trail
resource "cloudflare_r2_bucket_versioning" "artifacts_versioning" {
  account_id = var.cloudflare_account_id
  bucket     = cloudflare_r2_bucket.secureblog_artifacts.name
  
  versioning_configuration {
    status = "Enabled"
  }
}

# CORS configuration for secure access
resource "cloudflare_r2_bucket_cors" "artifacts_cors" {
  account_id = var.cloudflare_account_id
  bucket     = cloudflare_r2_bucket.secureblog_artifacts.name
  
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = [var.production_domain]
    expose_headers  = ["ETag", "Content-Type", "x-amz-meta-sha256"]
    max_age_seconds = 3600
  }
}

# Output bucket details
output "r2_bucket_endpoint" {
  value     = "https://${cloudflare_r2_bucket.secureblog_artifacts.name}.r2.cloudflarestorage.com"
  sensitive = false
}

output "r2_bucket_name" {
  value = cloudflare_r2_bucket.secureblog_artifacts.name
}

# Variables
variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "production_domain" {
  description = "Production domain for CORS"
  type        = string
  default     = "https://secureblog.example.com"
}