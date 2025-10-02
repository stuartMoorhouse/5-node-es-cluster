# DigitalOcean Spaces for searchable snapshot repository

locals {
  bucket_name = var.spaces_bucket_name != "" ? var.spaces_bucket_name : "${local.cluster_name_prefix}-snapshots"
}

# Spaces bucket for Elasticsearch snapshots
resource "digitalocean_spaces_bucket" "elasticsearch_snapshots" {
  name   = local.bucket_name
  region = var.region

  lifecycle_rule {
    enabled = true

    expiration {
      days = 90
    }
  }

  versioning {
    enabled = true
  }
}

# Spaces access key for Elasticsearch
resource "digitalocean_spaces_bucket_access_key" "elasticsearch" {
  spaces_access_key_name = "${local.cluster_name_prefix}-es-access"

  # Grant access to the snapshots bucket
  bucket_names = [digitalocean_spaces_bucket.elasticsearch_snapshots.name]
}

# CORS configuration for the bucket (if needed for web access)
resource "digitalocean_spaces_bucket_cors_configuration" "elasticsearch" {
  bucket = digitalocean_spaces_bucket.elasticsearch_snapshots.name
  region = digitalocean_spaces_bucket.elasticsearch_snapshots.region

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://*"]
    max_age_seconds = 3000
  }
}