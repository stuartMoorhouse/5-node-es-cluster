locals {
  common_tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
    ManagedBy   = "terraform"
  }

  cluster_name_prefix = "${var.cluster_name}-${var.environment}"

  # Master node IPs for cluster formation
  master_ips = join(",", [for i in range(var.hot_node_count) : "10.10.10.${4 + i}"])

  # Dollar sign for bash command substitutions in templates
  dollar = "$"

  # Calculate actual count for data sources based on new or legacy variables
  actual_cribl_count = var.data_source_type == "cribl" ? var.data_source_count : var.cribl_stream_count

  # Validation: Check if Spaces credentials are required but not provided
  validate_spaces = (var.enable_frozen_tier && var.spaces_access_id == "") ? tobool("ERROR: Frozen tier requires Spaces credentials. Set spaces_access_id and spaces_secret_key in terraform.tfvars") : true
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

# SSH Key data source
data "digitalocean_ssh_key" "main" {
  name = var.ssh_key_name
}

# Hot nodes (3 nodes with 8GB RAM) - Master eligible
resource "digitalocean_droplet" "hot_nodes" {
  count = var.hot_node_count

  name   = "${local.cluster_name_prefix}-hot-${count.index + 1}"
  region = var.region
  size   = var.hot_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    data.digitalocean_ssh_key.main.id
  ]

  user_data = var.deployment_mode == "airgapped" ? templatefile(
    "${path.module}/scripts/install_elasticsearch_airgapped.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      node_number          = count.index + 1
      total_masters        = var.hot_node_count
      master_ips           = local.master_ips
      is_first_node        = count.index == 0 ? "true" : "false"
      monitor_password     = random_password.monitor_password.result
      ingest_password      = random_password.ingest_password.result
      admin_password       = random_password.admin_password.result
      dollar               = local.dollar
    }
    ) : templatefile(
    "${path.module}/scripts/install_elasticsearch_networked.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      node_number          = count.index + 1
      total_masters        = var.hot_node_count
      master_ips           = local.master_ips
      is_first_node        = count.index == 0 ? "true" : "false"
      monitor_password     = random_password.monitor_password.result
      ingest_password      = random_password.ingest_password.result
      admin_password       = random_password.admin_password.result
      dollar               = local.dollar
    }
  )

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "hot-node", "master-eligible"]
  )
}

# Cold node (1 node with 2GB RAM) - Optional
resource "digitalocean_droplet" "cold_node" {
  count = var.enable_cold_tier ? 1 : 0

  name   = "${local.cluster_name_prefix}-cold-1"
  region = var.region
  size   = var.cold_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    data.digitalocean_ssh_key.main.id
  ]

  user_data = var.deployment_mode == "airgapped" ? templatefile(
    "${path.module}/scripts/install_elasticsearch_airgapped.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      node_number          = 4
      total_masters        = var.hot_node_count
      master_ips           = local.master_ips
      is_first_node        = "false"
      monitor_password     = random_password.monitor_password.result
      ingest_password      = random_password.ingest_password.result
      admin_password       = random_password.admin_password.result
      dollar               = local.dollar
    }
    ) : templatefile(
    "${path.module}/scripts/install_elasticsearch_networked.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      node_number          = 4
      total_masters        = var.hot_node_count
      master_ips           = local.master_ips
      is_first_node        = "false"
      monitor_password     = random_password.monitor_password.result
      ingest_password      = random_password.ingest_password.result
      admin_password       = random_password.admin_password.result
      dollar               = local.dollar
    }
  )

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "cold-node"]
  )

  depends_on = [digitalocean_droplet.hot_nodes]
}

# Frozen node (1 node with 2GB RAM) - Optional
resource "digitalocean_droplet" "frozen_node" {
  count = var.enable_frozen_tier ? 1 : 0

  name   = "${local.cluster_name_prefix}-frozen-1"
  region = var.region
  size   = var.frozen_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    data.digitalocean_ssh_key.main.id
  ]

  user_data = var.deployment_mode == "airgapped" ? templatefile(
    "${path.module}/scripts/install_elasticsearch_airgapped.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      node_number          = 5
      total_masters        = var.hot_node_count
      master_ips           = local.master_ips
      is_first_node        = "false"
      monitor_password     = random_password.monitor_password.result
      ingest_password      = random_password.ingest_password.result
      admin_password       = random_password.admin_password.result
      dollar               = local.dollar
    }
    ) : templatefile(
    "${path.module}/scripts/install_elasticsearch_networked.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      node_number          = 5
      total_masters        = var.hot_node_count
      master_ips           = local.master_ips
      is_first_node        = "false"
      monitor_password     = random_password.monitor_password.result
      ingest_password      = random_password.ingest_password.result
      admin_password       = random_password.admin_password.result
      dollar               = local.dollar
    }
  )

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "frozen-node"]
  )

  depends_on = [digitalocean_droplet.hot_nodes]
}

# No load balancer needed - Elasticsearch handles load balancing internally
# Hot nodes act as coordinators and distribute requests automatically

# Air-gapped package upload - Hot nodes
resource "null_resource" "upload_packages_hot" {
  count = var.deployment_mode == "airgapped" ? var.hot_node_count : 0

  triggers = {
    droplet_id = digitalocean_droplet.hot_nodes[count.index].id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.hot_nodes[count.index].ipv4_address
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  # Create directory for packages
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/elasticsearch-install/{elasticsearch,java,dependencies}",
      "chmod 755 /tmp/elasticsearch-install"
    ]
  }

  # Upload Elasticsearch package
  provisioner "file" {
    source      = "${path.module}/packages/elasticsearch/"
    destination = "/tmp/elasticsearch-install/elasticsearch/"
  }

  # Upload Java packages
  provisioner "file" {
    source      = "${path.module}/packages/java/"
    destination = "/tmp/elasticsearch-install/java/"
  }

  # Upload dependencies
  provisioner "file" {
    source      = "${path.module}/packages/dependencies/"
    destination = "/tmp/elasticsearch-install/dependencies/"
  }

  depends_on = [digitalocean_droplet.hot_nodes]
}

# Air-gapped package upload - Cold node
resource "null_resource" "upload_packages_cold" {
  count = var.deployment_mode == "airgapped" && var.enable_cold_tier ? 1 : 0

  triggers = {
    droplet_id = digitalocean_droplet.cold_node[0].id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.cold_node[0].ipv4_address
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  # Create directory for packages
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/elasticsearch-install/{elasticsearch,java,dependencies}",
      "chmod 755 /tmp/elasticsearch-install"
    ]
  }

  # Upload Elasticsearch package
  provisioner "file" {
    source      = "${path.module}/packages/elasticsearch/"
    destination = "/tmp/elasticsearch-install/elasticsearch/"
  }

  # Upload Java packages
  provisioner "file" {
    source      = "${path.module}/packages/java/"
    destination = "/tmp/elasticsearch-install/java/"
  }

  # Upload dependencies
  provisioner "file" {
    source      = "${path.module}/packages/dependencies/"
    destination = "/tmp/elasticsearch-install/dependencies/"
  }

  depends_on = [digitalocean_droplet.cold_node]
}

# Air-gapped package upload - Frozen node
resource "null_resource" "upload_packages_frozen" {
  count = var.deployment_mode == "airgapped" && var.enable_frozen_tier ? 1 : 0

  triggers = {
    droplet_id = digitalocean_droplet.frozen_node[0].id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.frozen_node[0].ipv4_address
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "5m"
  }

  # Create directory for packages
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/elasticsearch-install/{elasticsearch,java,dependencies}",
      "chmod 755 /tmp/elasticsearch-install"
    ]
  }

  # Upload Elasticsearch package
  provisioner "file" {
    source      = "${path.module}/packages/elasticsearch/"
    destination = "/tmp/elasticsearch-install/elasticsearch/"
  }

  # Upload Java packages
  provisioner "file" {
    source      = "${path.module}/packages/java/"
    destination = "/tmp/elasticsearch-install/java/"
  }

  # Upload dependencies
  provisioner "file" {
    source      = "${path.module}/packages/dependencies/"
    destination = "/tmp/elasticsearch-install/dependencies/"
  }

  depends_on = [digitalocean_droplet.frozen_node]
}