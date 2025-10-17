# DigitalOcean Spaces for searchable snapshot repository
# Automatically created when cold or frozen tiers are enabled

locals {
  bucket_name = var.spaces_bucket_name != "" ? var.spaces_bucket_name : "${local.cluster_name_prefix}-snapshots"

  # Determine if Spaces is needed based on tier configuration
  # Check if cold or frozen tiers are enabled in elasticsearch_nodes
  spaces_needed = (
    try(var.elasticsearch_nodes.cold.count, 0) > 0 ||
    try(var.elasticsearch_nodes.frozen.count, 0) > 0
  )

  # Create Spaces if needed AND credentials are provided
  spaces_enabled = local.spaces_needed && var.spaces_access_id != ""
}

# Spaces bucket for Elasticsearch snapshots
resource "digitalocean_spaces_bucket" "elasticsearch_snapshots" {
  count = local.spaces_enabled ? 1 : 0

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
resource "digitalocean_spaces_key" "elasticsearch" {
  count = local.spaces_enabled ? 1 : 0

  name = "${local.cluster_name_prefix}-es-access"
}

# CORS configuration for the bucket (if needed for web access)
resource "digitalocean_spaces_bucket_cors_configuration" "elasticsearch" {
  count = local.spaces_enabled ? 1 : 0

  bucket = digitalocean_spaces_bucket.elasticsearch_snapshots[0].name
  region = digitalocean_spaces_bucket.elasticsearch_snapshots[0].region

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://*"]
    max_age_seconds = 3000
  }
}