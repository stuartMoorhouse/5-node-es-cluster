# Firewall rules for Elasticsearch cluster - Principle of Least Privilege
resource "digitalocean_firewall" "elasticsearch" {
  name = "${local.cluster_name_prefix}-firewall"

  droplet_ids = concat(
    digitalocean_droplet.hot_nodes[*].id,
    [digitalocean_droplet.cold_node.id],
    [digitalocean_droplet.frozen_node.id]
  )

  # INBOUND RULES

  # Allow SSH access from specified IPs only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_ips != [] ? var.allowed_ssh_ips : var.allowed_ips
  }

  # Allow Elasticsearch HTTPS API access from allowed IPs
  # Hot nodes act as coordinators and handle load balancing internally
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9200"
    source_addresses = var.allowed_ips
  }

  # Allow Elasticsearch transport protocol between nodes (internal only)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9300"
    source_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # OUTBOUND RULES - Restrictive

  # HTTPS for package updates and external services
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0"]
  }

  # HTTP for package updates (some repos still use HTTP)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0"]
  }

  # Elasticsearch transport between nodes
  outbound_rule {
    protocol              = "tcp"
    port_range            = "9300"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # Elasticsearch HTTP between nodes (for cross-cluster operations)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "9200"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # DNS resolution
  outbound_rule {
    protocol              = "tcp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0"]
  }

  # NTP for time synchronization
  outbound_rule {
    protocol              = "udp"
    port_range            = "123"
    destination_addresses = ["0.0.0.0/0"]
  }

  # ICMP for network diagnostics (restricted)
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  tags = keys(local.common_tags)
}

# Load balancer firewall removed - direct client access to nodes instead