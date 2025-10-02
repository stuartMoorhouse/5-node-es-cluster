locals {
  common_tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
    ManagedBy   = "terraform"
  }

  cluster_name_prefix = "${var.cluster_name}-${var.environment}"
}

# Random password for Elasticsearch cluster
resource "random_password" "elastic_password" {
  length  = 32
  special = true
}

# VPC for cluster isolation
resource "digitalocean_vpc" "elasticsearch" {
  name     = "${local.cluster_name_prefix}-vpc"
  region   = var.region
  ip_range = "10.10.10.0/24"
}

# SSH Key data source
data "digitalocean_ssh_key" "main" {
  name = var.ssh_key_name
}

# Cloud-init script for Elasticsearch installation
locals {
  elasticsearch_init = templatefile("${path.module}/scripts/install_elasticsearch.sh", {
    elasticsearch_version = var.elasticsearch_version
    elastic_password      = random_password.elastic_password.result
    cluster_name         = local.cluster_name_prefix
  })
}

# Hot nodes (3 nodes with 8GB RAM)
resource "digitalocean_droplet" "hot_nodes" {
  count = var.hot_node_count

  name   = "${local.cluster_name_prefix}-hot-${count.index + 1}"
  region = var.region
  size   = var.hot_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [data.digitalocean_ssh_key.main.id]

  user_data = local.elasticsearch_init

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "hot-node"]
  )
}

# Cold node (1 node with 2GB RAM)
resource "digitalocean_droplet" "cold_node" {
  name   = "${local.cluster_name_prefix}-cold-1"
  region = var.region
  size   = var.cold_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [data.digitalocean_ssh_key.main.id]

  user_data = local.elasticsearch_init

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "cold-node"]
  )
}

# Frozen node (1 node with 2GB RAM)
resource "digitalocean_droplet" "frozen_node" {
  name   = "${local.cluster_name_prefix}-frozen-1"
  region = var.region
  size   = var.frozen_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [data.digitalocean_ssh_key.main.id]

  user_data = local.elasticsearch_init

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "frozen-node"]
  )
}

# Load balancer for cluster access
resource "digitalocean_loadbalancer" "elasticsearch" {
  name   = "${local.cluster_name_prefix}-lb"
  region = var.region

  forwarding_rule {
    entry_port     = 9200
    entry_protocol = "https"
    target_port    = 9200
    target_protocol = "https"
    tls_passthrough = true
  }

  healthcheck {
    port     = 9200
    protocol = "tcp"
  }

  droplet_ids = concat(
    digitalocean_droplet.hot_nodes[*].id,
    [digitalocean_droplet.cold_node.id],
    [digitalocean_droplet.frozen_node.id]
  )

  vpc_uuid = digitalocean_vpc.elasticsearch.id
}