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

  user_data = templatefile(
    "${path.module}/scripts/install_kibana.sh",
    {
      elasticsearch_version = var.elasticsearch_version
      elastic_password      = random_password.elastic_password.result
      cluster_name         = local.cluster_name_prefix
      master_ips           = local.master_ips
      deployment_mode      = var.deployment_mode
      epr_url              = var.deployment_mode == "airgapped" ? "http://10.10.10.3:8443" : ""
      artifact_registry_url = var.deployment_mode == "airgapped" ? "http://10.10.10.2:9080/downloads/" : ""
      dollar               = local.dollar
    }
  )

  tags = concat(
    keys(local.common_tags),
    ["elasticsearch", "kibana"]
  )

  depends_on = [digitalocean_droplet.elasticsearch_nodes]
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
