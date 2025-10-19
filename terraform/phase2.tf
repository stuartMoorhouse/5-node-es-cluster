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
    digitalocean_ssh_key.main.id
  ]

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "kibana"]
  )

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = file("~/.ssh/id_ed25519")
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install_kibana.sh"
    destination = "/tmp/install_kibana.sh"
  }

  # Create directory for CA certificate
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /etc/kibana/certs",
      "chmod 755 /etc/kibana/certs"
    ]
  }

  depends_on = [digitalocean_droplet.elasticsearch_nodes]
}

# Copy CA certificate from first ES master to Kibana
# This is required for proper SSL verification
resource "null_resource" "copy_ca_to_kibana" {
  # Trigger whenever Kibana or ES nodes change
  triggers = {
    kibana_id = digitalocean_droplet.kibana.id
    es_master_id = values(digitalocean_droplet.elasticsearch_nodes)[0].id
  }

  # Use local-exec to download CA cert and kibana_system password from ES master, then upload to Kibana
  provisioner "local-exec" {
    command = <<-EOT
      # Download CA cert from first ES master
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ~/.ssh/id_ed25519 \
        root@${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address}:/etc/elasticsearch/certs/ca.crt \
        /tmp/es-ca.crt || \
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ~/.ssh/id_ed25519 \
        root@${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address}:/etc/elasticsearch/certs/http_ca.crt \
        /tmp/es-ca.crt

      # Download password files from ES master
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ~/.ssh/id_ed25519 \
        root@${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address}:/root/.kibana_system_password \
        /tmp/kibana_system_password || true

      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ~/.ssh/id_ed25519 \
        root@${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address}:/root/.elastic_password \
        /tmp/elastic_password || true

      # Upload CA cert to Kibana
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ~/.ssh/id_ed25519 \
        /tmp/es-ca.crt \
        root@${digitalocean_droplet.kibana.ipv4_address}:/etc/kibana/certs/ca.crt

      # Upload password files to Kibana
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ~/.ssh/id_ed25519 \
        /tmp/kibana_system_password \
        root@${digitalocean_droplet.kibana.ipv4_address}:/root/.kibana_system_password || true

      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i ~/.ssh/id_ed25519 \
        /tmp/elastic_password \
        root@${digitalocean_droplet.kibana.ipv4_address}:/root/.elastic_password || true

      # Cleanup local temp files
      rm -f /tmp/es-ca.crt /tmp/kibana_system_password /tmp/elastic_password
    EOT
  }

  depends_on = [digitalocean_droplet.kibana, digitalocean_droplet.elasticsearch_nodes]
}

# Install Kibana after CA cert is copied
resource "null_resource" "install_kibana" {
  triggers = {
    kibana_id = digitalocean_droplet.kibana.id
    ca_copied = null_resource.copy_ca_to_kibana.id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.kibana.ipv4_address
    private_key = file("~/.ssh/id_ed25519")
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install_kibana.sh",
      "ES_VERSION='${var.elasticsearch_version}' CLUSTER_NAME='${local.cluster_name_prefix}' MASTER_IPS='${local.actual_master_ips}' DEPLOYMENT_MODE='${var.deployment_mode}' EPR_URL='${var.deployment_mode == "airgapped" ? "http://10.10.10.3:8443" : ""}' ARTIFACT_REGISTRY_URL='${var.deployment_mode == "airgapped" ? "http://10.10.10.2:9080/downloads/" : ""}' /tmp/install_kibana.sh"
    ]
  }

  depends_on = [null_resource.copy_ca_to_kibana]
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
    digitalocean_ssh_key.main.id
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
    digitalocean_ssh_key.main.id
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
