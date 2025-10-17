# Data Source VMs - Cribl Stream
# Optional VMs for sending data to Elasticsearch via Cribl Stream

# Cribl Stream droplets
resource "digitalocean_droplet" "cribl_stream" {
  count = var.cribl_stream_count

  name   = "${local.cluster_name_prefix}-cribl-${count.index + 1}"
  region = var.region
  size   = var.cribl_stream_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    data.digitalocean_ssh_key.main.id
  ]

  user_data = var.deployment_mode == "airgapped" ? templatefile(
    "${path.module}/scripts/install_cribl_airgapped.sh",
    {
      cribl_version         = var.cribl_stream_version
      cribl_leader_mode     = var.cribl_leader_mode
      cribl_leader_url      = var.cribl_leader_url
      cribl_auth_token      = var.cribl_auth_token
      elasticsearch_url     = "https://${digitalocean_droplet.hot_nodes[0].ipv4_address_private}:9200"
      elasticsearch_password = random_password.ingest_password.result
      dollar                = local.dollar
    }
    ) : templatefile(
    "${path.module}/scripts/install_cribl_networked.sh",
    {
      cribl_version         = var.cribl_stream_version
      cribl_leader_mode     = var.cribl_leader_mode
      cribl_leader_url      = var.cribl_leader_url
      cribl_auth_token      = var.cribl_auth_token
      elasticsearch_url     = "https://${digitalocean_droplet.hot_nodes[0].ipv4_address_private}:9200"
      elasticsearch_password = random_password.ingest_password.result
      dollar                = local.dollar
    }
  )

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "data-source", "cribl-stream"]
  )

  depends_on = [digitalocean_droplet.hot_nodes]
}

# Air-gapped package upload - Cribl Stream nodes
resource "null_resource" "upload_packages_cribl" {
  count = var.deployment_mode == "airgapped" && var.cribl_stream_count > 0 ? var.cribl_stream_count : 0

  triggers = {
    droplet_id = digitalocean_droplet.cribl_stream[count.index].id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.cribl_stream[count.index].ipv4_address
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  # Create directory for packages
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/cribl-install",
      "chmod 755 /tmp/cribl-install"
    ]
  }

  # Upload Cribl package
  provisioner "file" {
    source      = "${path.module}/packages/cribl/"
    destination = "/tmp/cribl-install/"
  }

  depends_on = [digitalocean_droplet.cribl_stream]
}
