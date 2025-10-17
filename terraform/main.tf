locals {
  common_tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
    ManagedBy   = "terraform"
  }

  cluster_name_prefix = "${var.cluster_name}-${var.environment}"

  # Dollar sign for bash command substitutions in templates
  dollar = "$"

  # Calculate actual count for data sources based on new or legacy variables
  actual_cribl_count = var.data_source_type == "cribl" ? var.data_source_count : var.cribl_stream_count

  # Flatten elasticsearch_nodes into individual node instances
  # Creates entries like: { "hot-1" = {...}, "hot-2" = {...}, "cold-1" = {...} }
  # First, create a flat list with index positions
  es_nodes_list = flatten([
    for node_type, config in var.elasticsearch_nodes : [
      for i in range(config.count) : {
        key         = "${node_type}-${i + 1}"
        node_type   = node_type
        node_number = i + 1
        size        = config.size
        roles       = config.roles
        is_master   = contains(config.roles, "master")
      }
    ]
  ])

  # Convert to map and assign IPs based on list index
  es_nodes_flat = {
    for idx, node in local.es_nodes_list :
    node.key => merge(node, {
      private_ip = "10.10.10.${4 + idx}"
    })
  }

  # Get list of master-eligible node IPs for cluster formation
  master_nodes = [for k, v in local.es_nodes_flat : v if v.is_master]
  master_ips   = join(",", [for node in local.master_nodes : node.private_ip])

  # Total number of master-eligible nodes
  total_masters = length(local.master_nodes)

  # Check if frozen tier requires Spaces credentials
  has_frozen_tier = try(var.elasticsearch_nodes.frozen.count, 0) > 0
  validate_spaces = (local.has_frozen_tier && var.spaces_access_id == "") ? tobool("ERROR: Frozen tier requires Spaces credentials. Set spaces_access_id and spaces_secret_key in terraform.tfvars") : true
}

# Random passwords for Elasticsearch users
resource "random_password" "elastic_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*+-=?@^_~" # Exclude problematic characters like (){}[]<>
}

resource "random_password" "monitor_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*+-=?@^_~"
}

resource "random_password" "ingest_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*+-=?@^_~"
}

resource "random_password" "admin_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*+-=?@^_~"
}

# VPC for cluster isolation
resource "digitalocean_vpc" "elasticsearch" {
  name     = "${local.cluster_name_prefix}-vpc"
  region   = var.region
  ip_range = "10.10.10.0/24"
}

# Create SSH key in DigitalOcean using your local public key
resource "digitalocean_ssh_key" "main" {
  name       = var.ssh_key_name
  public_key = var.ssh_public_key
}

# Elasticsearch nodes - unified resource using for_each
# Creates all nodes dynamically based on var.elasticsearch_nodes configuration
resource "digitalocean_droplet" "elasticsearch_nodes" {
  for_each = local.es_nodes_flat

  name   = "${local.cluster_name_prefix}-${each.key}"
  region = var.region
  size   = each.value.size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    digitalocean_ssh_key.main.id
  ]

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "${each.value.node_type}-node"],
    each.value.is_master ? ["master-eligible"] : []
  )

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = file("~/.ssh/id_ed25519")
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install_elasticsearch.sh"
    destination = "/tmp/install_elasticsearch.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install_elasticsearch.sh",
      "ES_VERSION='${var.elasticsearch_version}' \\",
      "ELASTIC_PASSWORD='${random_password.elastic_password.result}' \\",
      "CLUSTER_NAME='${local.cluster_name_prefix}' \\",
      "NODE_NUMBER='${each.value.node_number}' \\",
      "TOTAL_MASTERS='${local.total_masters}' \\",
      "MASTER_IPS='${local.master_ips}' \\",
      "IS_FIRST_NODE='${each.key == keys(local.es_nodes_flat)[0] ? "true" : "false"}' \\",
      "MONITOR_PASSWORD='${random_password.monitor_password.result}' \\",
      "INGEST_PASSWORD='${random_password.ingest_password.result}' \\",
      "ADMIN_PASSWORD='${random_password.admin_password.result}' \\",
      "PRIVATE_IP='${self.ipv4_address_private}' \\",
      "NODE_ROLES='${join(",", each.value.roles)}' \\",
      "/tmp/install_elasticsearch.sh"
    ]
  }
}

# No load balancer needed - Elasticsearch handles load balancing internally
# Master-eligible nodes act as coordinators and distribute requests automatically