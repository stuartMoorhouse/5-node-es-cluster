variable "digitalocean_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "spaces_access_id" {
  description = "DigitalOcean Spaces access key ID (required for Spaces bucket creation)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "spaces_secret_key" {
  description = "DigitalOcean Spaces secret access key (required for Spaces bucket creation)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cluster_name" {
  description = "Name prefix for the Elasticsearch cluster resources"
  type        = string
  default     = "elasticsearch"
}

variable "region" {
  description = "DigitalOcean region for resources"
  type        = string
  default     = "nyc3"
}

variable "environment" {
  description = "Environment name (e.g., poc, dev, staging)"
  type        = string
  default     = "poc"
}

variable "elasticsearch_version" {
  description = "Elasticsearch version to install"
  type        = string
  default     = "9.1.5" # Latest stable version
}

variable "hot_node_count" {
  description = "Number of hot data nodes (minimum 1 for single-node demo, 2+ recommended for production quorum)"
  type        = number
  default     = 1  # Minimal for demo - use 3 for production

  validation {
    condition     = var.hot_node_count >= 1 && var.hot_node_count <= 10
    error_message = "hot_node_count must be between 1 and 10"
  }
}

variable "hot_node_size" {
  description = "Droplet size for hot nodes - Production: s-4vcpu-8gb, Demo: s-2vcpu-2gb, Minimal: s-1vcpu-2gb"
  type        = string
  default     = "s-2vcpu-2gb"  # Cost-optimized for demo (~$18/month each)
  # Production: "s-4vcpu-8gb" ($48/month each)
  # Minimal demo: "s-1vcpu-2gb" ($12/month each) - works but very limited performance
}

variable "cold_node_size" {
  description = "Droplet size for cold node - Recommended: s-1vcpu-2gb minimum"
  type        = string
  default     = "s-1vcpu-2gb"  # Minimum recommended (~$12/month)
  # Production: "s-1vcpu-2gb" or larger
}

variable "frozen_node_size" {
  description = "Droplet size for frozen node - Recommended: s-1vcpu-2gb minimum"
  type        = string
  default     = "s-1vcpu-2gb"  # Minimum recommended (~$12/month)
  # Production: "s-1vcpu-2gb" or larger
}

variable "ssh_key_name" {
  description = "Name of the SSH key in DigitalOcean"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning (used to upload air-gapped packages)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "allowed_ips" {
  description = "List of IP addresses allowed to access Elasticsearch API"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Open to internet, restrict in production
}

variable "allowed_ssh_ips" {
  description = "List of IP addresses allowed SSH access (more restrictive than API access)"
  type        = list(string)
  default     = [] # If empty, falls back to allowed_ips
}

variable "spaces_bucket_name" {
  description = "Name for the DigitalOcean Spaces bucket for snapshots"
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable DigitalOcean monitoring on droplets"
  type        = bool
  default     = true
}

variable "kibana_node_size" {
  description = "Droplet size for Kibana - Production: s-2vcpu-4gb, Demo: s-1vcpu-2gb"
  type        = string
  default     = "s-1vcpu-2gb"  # Cost-optimized for demo (~$12/month)
  # Production: "s-2vcpu-4gb" ($24/month) for better performance
}

variable "epr_node_size" {
  description = "Droplet size for EPR server - Minimum: s-1vcpu-2gb"
  type        = string
  default     = "s-1vcpu-2gb"  # Minimum recommended (~$12/month)
  # Can use s-1vcpu-1gb ($6/month) for very light usage
}

variable "artifact_registry_node_size" {
  description = "Droplet size for Artifact Registry - Minimum: s-1vcpu-2gb"
  type        = string
  default     = "s-1vcpu-2gb"  # Minimum recommended (~$12/month)
  # Can use s-1vcpu-1gb ($6/month) for very light usage
}

# Deployment Configuration
variable "deployment_type" {
  description = "Elasticsearch deployment type: 'self-managed' (VMs), 'elastic-cloud-hosted' (future), 'elastic-cloud-serverless' (future)"
  type        = string
  default     = "self-managed"

  validation {
    condition     = contains(["self-managed", "elastic-cloud-hosted", "elastic-cloud-serverless"], var.deployment_type)
    error_message = "deployment_type must be 'self-managed', 'elastic-cloud-hosted', or 'elastic-cloud-serverless'"
  }
}

variable "deployment_mode" {
  description = "Installation mode for self-managed: 'airgapped' (packages pre-downloaded) or 'normal' (install from internet)"
  type        = string
  default     = "normal"

  validation {
    condition     = contains(["airgapped", "normal"], var.deployment_mode)
    error_message = "deployment_mode must be either 'airgapped' or 'normal'"
  }
}

# Cluster Tier Configuration
variable "enable_cold_tier" {
  description = "Enable cold data tier (1 node with 2GB RAM for older data)"
  type        = bool
  default     = false
}

variable "enable_frozen_tier" {
  description = "Enable frozen data tier (1 node with 2GB RAM for archived data with searchable snapshots). Requires Spaces credentials."
  type        = bool
  default     = false
}

# Data Source Configuration
variable "data_source_type" {
  description = "Data source VM type to deploy: 'none', 'cribl'"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "cribl"], var.data_source_type)
    error_message = "data_source_type must be 'none' or 'cribl'"
  }
}

variable "data_source_count" {
  description = "Number of data source VMs to create (1-10, only used if data_source_type is not 'none')"
  type        = number
  default     = 1

  validation {
    condition     = var.data_source_count >= 1 && var.data_source_count <= 10
    error_message = "data_source_count must be between 1 and 10"
  }
}

# Legacy variable for backward compatibility - will be deprecated
variable "cribl_stream_count" {
  description = "DEPRECATED: Use data_source_type='cribl' and data_source_count instead. Number of Cribl Stream VMs to create (0 to disable)"
  type        = number
  default     = 0

  validation {
    condition     = var.cribl_stream_count >= 0 && var.cribl_stream_count <= 10
    error_message = "cribl_stream_count must be between 0 and 10"
  }
}

variable "cribl_stream_node_size" {
  description = "Droplet size for Cribl Stream - Recommended: s-2vcpu-4gb minimum"
  type        = string
  default     = "s-2vcpu-4gb"  # Recommended for processing (~$24/month)
  # Production: "s-4vcpu-8gb" ($48/month) for heavy workloads
}

variable "cribl_stream_version" {
  description = "Cribl Stream version to install"
  type        = string
  default     = "4.8.2"  # Latest stable version
}

variable "cribl_leader_mode" {
  description = "Cribl deployment mode: 'standalone' or 'worker' (worker requires external leader)"
  type        = string
  default     = "standalone"

  validation {
    condition     = contains(["standalone", "worker"], var.cribl_leader_mode)
    error_message = "cribl_leader_mode must be either 'standalone' or 'worker'"
  }
}

variable "cribl_leader_url" {
  description = "URL of Cribl Leader (only required if cribl_leader_mode is 'worker')"
  type        = string
  default     = ""
}

variable "cribl_auth_token" {
  description = "Cribl worker auth token (only required if cribl_leader_mode is 'worker')"
  type        = string
  default     = ""
  sensitive   = true
}