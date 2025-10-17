# Firewall rules for Elasticsearch cluster - Principle of Least Privilege
resource "digitalocean_firewall" "elasticsearch" {
  name = "${local.cluster_name_prefix}-firewall"

  droplet_ids = [for k, node in digitalocean_droplet.elasticsearch_nodes : node.id]

  # INBOUND RULES

  # Allow SSH access from specified IPs only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_ips != [] ? var.allowed_ssh_ips : var.allowed_ips
  }

  # Allow Elasticsearch HTTPS API access from allowed IPs AND VPC (for Kibana, Cribl, etc.)
  # Hot nodes act as coordinators and handle load balancing internally
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9200"
    source_addresses = concat(var.allowed_ips, [digitalocean_vpc.elasticsearch.ip_range])
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

# Firewall for Kibana, EPR, and Artifact Registry
resource "digitalocean_firewall" "elastic_services" {
  name  = "${local.cluster_name_prefix}-services-firewall"

  droplet_ids = var.deployment_mode == "airgapped" ? concat(
    [digitalocean_droplet.kibana.id],
    digitalocean_droplet.epr[*].id,
    digitalocean_droplet.artifact_registry[*].id
    ) : [
    digitalocean_droplet.kibana.id
  ]

  # INBOUND RULES

  # Allow SSH access from specified IPs only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_ips != [] ? var.allowed_ssh_ips : var.allowed_ips
  }

  # Allow Kibana HTTPS access from allowed IPs
  inbound_rule {
    protocol         = "tcp"
    port_range       = "5601"
    source_addresses = var.allowed_ips
  }

  # Allow EPR access from VPC only (internal)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8443"
    source_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # Allow Artifact Registry access from VPC only (internal)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9080"
    source_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # OUTBOUND RULES

  # HTTPS for external services
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0"]
  }

  # HTTP for package updates
  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0"]
  }

  # Access to Elasticsearch nodes
  outbound_rule {
    protocol              = "tcp"
    port_range            = "9200"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # Access to EPR (from Kibana)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "8443"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # Access to Artifact Registry (from Kibana/Fleet)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "9080"
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

  # ICMP for network diagnostics (restricted to VPC)
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  tags = keys(local.common_tags)
}

# Firewall for Data Source VMs (Cribl Stream)
resource "digitalocean_firewall" "cribl_stream" {
  count = local.actual_cribl_count > 0 ? 1 : 0

  name = "${local.cluster_name_prefix}-cribl-firewall"

  droplet_ids = digitalocean_droplet.cribl_stream[*].id

  # INBOUND RULES

  # Allow SSH access from specified IPs only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_ips != [] ? var.allowed_ssh_ips : var.allowed_ips
  }

  # Allow Cribl UI access from allowed IPs
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9000"
    source_addresses = var.allowed_ips
  }

  # Allow data input ports (common log collection ports)
  # Syslog TCP
  inbound_rule {
    protocol         = "tcp"
    port_range       = "514"
    source_addresses = var.allowed_ips
  }

  # Syslog UDP
  inbound_rule {
    protocol         = "udp"
    port_range       = "514"
    source_addresses = var.allowed_ips
  }

  # HTTP Event Collector (HEC) compatible
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8088"
    source_addresses = var.allowed_ips
  }

  # Raw TCP input
  inbound_rule {
    protocol         = "tcp"
    port_range       = "10001"
    source_addresses = var.allowed_ips
  }

  # S3 input (internal communication)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "10200"
    source_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # OUTBOUND RULES

  # Access to Elasticsearch nodes (HTTPS API)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "9200"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  # HTTPS for external services (networked mode)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0"]
  }

  # HTTP for package updates (networked mode)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0"]
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

  # ICMP for network diagnostics (VPC only)
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = [digitalocean_vpc.elasticsearch.ip_range]
  }

  tags = keys(local.common_tags)
}