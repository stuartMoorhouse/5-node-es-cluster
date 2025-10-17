# Kibana, EPR, and Artifact Registry
# Additional components for the full Elastic Stack deployment

# Kibana droplet
resource "digitalocean_droplet" "kibana" {
  name   = "${local.cluster_name_prefix}-kibana"
  region = var.region
  size   = var.kibana_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    data.digitalocean_ssh_key.main.id
  ]

  user_data = var.deployment_mode == "airgapped" ? templatefile(
    "${path.module}/scripts/install_kibana_airgapped.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      master_ips           = local.master_ips
      epr_url              = "http://10.10.10.20:8443"
      artifact_registry_url = "http://10.10.10.21:9080"
      dollar               = local.dollar
    }
    ) : templatefile(
    "${path.module}/scripts/install_kibana_networked.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      master_ips           = local.master_ips
      dollar               = local.dollar
    }
  )

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "kibana"]
  )

  depends_on = [digitalocean_droplet.hot_nodes]
}

# EPR (Elastic Package Registry) server droplet - Air-gapped mode only
resource "digitalocean_droplet" "epr" {
  count = var.deployment_mode == "airgapped" ? 1 : 0

  name   = "${local.cluster_name_prefix}-epr"
  region = var.region
  size   = var.epr_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    data.digitalocean_ssh_key.main.id
  ]

  user_data = templatefile("${path.module}/scripts/install_epr_airgapped.sh", {
    elasticsearch_version = var.elasticsearch_version
    dollar               = local.dollar
  })

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "epr"]
  )
}

# Artifact Registry server droplet - Air-gapped mode only
resource "digitalocean_droplet" "artifact_registry" {
  count = var.deployment_mode == "airgapped" ? 1 : 0

  name   = "${local.cluster_name_prefix}-artifacts"
  region = var.region
  size   = var.artifact_registry_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    data.digitalocean_ssh_key.main.id
  ]

  user_data = templatefile("${path.module}/scripts/install_artifact_registry_airgapped.sh", {
    elasticsearch_version = var.elasticsearch_version
    dollar               = local.dollar
  })

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "artifact-registry"]
  )
}

# Package upload for Kibana - Air-gapped mode only
resource "null_resource" "upload_packages_kibana" {
  count = var.deployment_mode == "airgapped" ? 1 : 0

  triggers = {
    droplet_id = digitalocean_droplet.kibana.id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.kibana.ipv4_address
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/elasticsearch-install/kibana",
      "chmod 755 /tmp/elasticsearch-install"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/packages/kibana/"
    destination = "/tmp/elasticsearch-install/kibana/"
  }

  depends_on = [digitalocean_droplet.kibana]
}

# Package upload for EPR - Air-gapped mode only
resource "null_resource" "upload_packages_epr" {
  count = var.deployment_mode == "airgapped" ? 1 : 0

  triggers = {
    droplet_id = digitalocean_droplet.epr[0].id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.epr.ipv4_address
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/elasticsearch-install/epr",
      "chmod 755 /tmp/elasticsearch-install"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/packages/epr/"
    destination = "/tmp/elasticsearch-install/epr/"
  }

  depends_on = [digitalocean_droplet.epr[0]]
}

# Package upload for Artifact Registry - Air-gapped mode only
resource "null_resource" "upload_packages_artifact_registry" {
  count = var.deployment_mode == "airgapped" ? 1 : 0

  triggers = {
    droplet_id = digitalocean_droplet.artifact_registry[0].id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.artifact_registry[0].ipv4_address
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/elasticsearch-install/{nginx,artifacts}",
      "chmod 755 /tmp/elasticsearch-install"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/packages/nginx/"
    destination = "/tmp/elasticsearch-install/nginx/"
  }

  provisioner "file" {
    source      = "${path.module}/packages/artifacts/"
    destination = "/tmp/elasticsearch-install/artifacts/"
  }

  depends_on = [digitalocean_droplet.artifact_registry[0]]
}
