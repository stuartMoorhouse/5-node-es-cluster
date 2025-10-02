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
  default     = "9.2.0" # Latest version as requested
}

variable "hot_node_count" {
  description = "Number of hot data nodes"
  type        = number
  default     = 3
}

variable "hot_node_size" {
  description = "Droplet size for hot nodes (8GB RAM)"
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "cold_node_size" {
  description = "Droplet size for cold node (2GB RAM)"
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "frozen_node_size" {
  description = "Droplet size for frozen node (2GB RAM)"
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "ssh_key_name" {
  description = "Name of the SSH key in DigitalOcean"
  type        = string
}

variable "allowed_ips" {
  description = "List of IP addresses allowed to access Elasticsearch"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Open to internet, restrict in production
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