# Data Source VMs - Cribl Stream
# Optional VMs for sending data to Elasticsearch via Cribl Stream
# Note: actual_cribl_count is calculated in main.tf locals

# Cribl Stream droplets
resource "digitalocean_droplet" "cribl_stream" {
  count = local.actual_cribl_count

  name   = "${local.cluster_name_prefix}-cribl-${count.index + 1}"
  region = var.region
  size   = var.cribl_stream_node_size
  image  = "ubuntu-22-04-x64"

  vpc_uuid   = digitalocean_vpc.elasticsearch.id
  monitoring = var.enable_monitoring

  ssh_keys = [
    digitalocean_ssh_key.main.id
  ]

  user_data = templatefile(
    "${path.module}/scripts/install_cribl.sh",
    {
      cribl_version         = var.cribl_stream_version
      cribl_leader_mode     = var.cribl_leader_mode
      cribl_leader_url      = var.cribl_leader_url
      cribl_auth_token      = var.cribl_auth_token
      elasticsearch_url     = "https://${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address_private}:9200"
      elasticsearch_password = random_password.ingest_password.result
      dollar                = local.dollar
    }
  )

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "data-source", "cribl-stream"]
  )

  depends_on = [digitalocean_droplet.elasticsearch_nodes]
}
