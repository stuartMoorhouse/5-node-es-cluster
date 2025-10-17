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

# Flexible node configuration - define any number of node types
variable "elasticsearch_nodes" {
  description = "Map of Elasticsearch node configurations. Key = node type name, Value = {count, size, roles}"
  type = map(object({
    count = number       # Number of nodes of this type (0 to disable)
    size  = string       # DigitalOcean droplet size
    roles = list(string) # Elasticsearch node roles
  }))

  default = {
    hot = {
      count = 1
      size  = "s-2vcpu-2gb"
      roles = ["master", "data_hot", "ingest", "remote_cluster_client"]
    }
    cold = {
      count = 0
      size  = "s-1vcpu-2gb"
      roles = ["data_cold", "remote_cluster_client"]
    }
    frozen = {
      count = 0
      size  = "s-1vcpu-2gb"
      roles = ["data_frozen", "remote_cluster_client"]
    }
  }

  validation {
    condition     = alltrue([for k, v in var.elasticsearch_nodes : v.count >= 0 && v.count <= 10])
    error_message = "Each node type count must be between 0 and 10"
  }

  validation {
    condition     = sum([for k, v in var.elasticsearch_nodes : v.count]) >= 1
    error_message = "Must have at least 1 Elasticsearch node configured"
  }
}

variable "ssh_public_key" {
  description = "Your SSH public key content (e.g., contents of ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"
  type        = string
}

variable "ssh_key_name" {
  description = "Name for the SSH key in DigitalOcean (will be created by Terraform)"
  type        = string
  default     = "elasticsearch-cluster-key"
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
  description = "Deployment mode: 'airgapped' (self-managed, no internet), 'networked' (self-managed, internet access), 'cloud_hosted' (Elastic Cloud hosted), 'cloud_serverless' (Elastic Cloud serverless)"
  type        = string
  default     = "networked"

  validation {
    condition     = contains(["airgapped", "networked", "cloud_hosted", "cloud_serverless"], var.deployment_mode)
    error_message = "deployment_mode must be 'airgapped', 'networked', 'cloud_hosted', or 'cloud_serverless'"
  }
}

# Cluster Tier Configuration
# NOTE: Cold and frozen tiers are now configured via the elasticsearch_nodes variable above
# Set count > 0 for the tier you want to enable

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