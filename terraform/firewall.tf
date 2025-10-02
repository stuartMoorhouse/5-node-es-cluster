# Firewall rules for Elasticsearch cluster
resource "digitalocean_firewall" "elasticsearch" {
  name = "${local.cluster_name_prefix}-firewall"

  droplet_ids = concat(
    digitalocean_droplet.hot_nodes[*].id,
    [digitalocean_droplet.cold_node.id],
    [digitalocean_droplet.frozen_node.id]
  )

  # Allow SSH access from specified IPs
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ips
  }

  # Allow Elasticsearch HTTP API access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9200"
    source_addresses = var.allowed_ips
  }

  # Allow Elasticsearch transport protocol between nodes (internal)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9300"
    source_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  tags = keys(local.common_tags)
}

# Firewall for load balancer access
resource "digitalocean_firewall" "elasticsearch_lb" {
  name = "${local.cluster_name_prefix}-lb-firewall"

  tags = ["${local.cluster_name_prefix}-lb"]

  # Allow HTTPS access to load balancer
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = var.allowed_ips
  }

  # Allow Elasticsearch API access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9200"
    source_addresses = var.allowed_ips
  }

  # Allow health checks from load balancer
  inbound_rule {
    protocol                  = "tcp"
    port_range               = "9200"
    source_load_balancer_uids = [digitalocean_loadbalancer.elasticsearch.id]
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}