output "cluster_name" {
  description = "Name of the Elasticsearch cluster"
  value       = local.cluster_name_prefix
}

output "elasticsearch_urls" {
  description = "URLs to access Elasticsearch cluster (all nodes)"
  value       = [for k, node in digitalocean_droplet.elasticsearch_nodes : "https://${node.ipv4_address}:9200"]
}

output "primary_elasticsearch_url" {
  description = "Primary URL for Elasticsearch access (first node)"
  value       = length(digitalocean_droplet.elasticsearch_nodes) > 0 ? "https://${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address}:9200" : "No nodes configured"
}

output "elasticsearch_password_command" {
  description = "Command to retrieve the Elasticsearch elastic user password from the first ES node"
  value       = length(digitalocean_droplet.elasticsearch_nodes) > 0 ? "ssh root@${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address} cat /root/.elastic_password" : "No nodes configured"
}

output "elasticsearch_node_ips" {
  description = "IP addresses of all Elasticsearch nodes by node name"
  value = {
    for k, node in digitalocean_droplet.elasticsearch_nodes :
    k => {
      public  = node.ipv4_address
      private = node.ipv4_address_private
      roles   = local.es_nodes_flat[k].roles
    }
  }
}

output "elasticsearch_nodes_by_type" {
  description = "Elasticsearch nodes grouped by type"
  value = {
    for node_type in distinct([for k, v in local.es_nodes_flat : v.node_type]) :
    node_type => [
      for k, node in digitalocean_droplet.elasticsearch_nodes :
      {
        name    = k
        public  = node.ipv4_address
        private = node.ipv4_address_private
      }
      if local.es_nodes_flat[k].node_type == node_type
    ]
  }
}

output "spaces_bucket_name" {
  description = "Name of the DigitalOcean Spaces bucket for snapshots"
  value       = length(digitalocean_spaces_bucket.elasticsearch_snapshots) > 0 ? digitalocean_spaces_bucket.elasticsearch_snapshots[0].name : "Not configured - add Spaces credentials to enable"
}

output "spaces_endpoint" {
  description = "Endpoint for the DigitalOcean Spaces bucket"
  value       = length(digitalocean_spaces_bucket.elasticsearch_snapshots) > 0 ? digitalocean_spaces_bucket.elasticsearch_snapshots[0].bucket_domain_name : "Not configured - add Spaces credentials to enable"
}

output "spaces_access_key" {
  description = "Access key ID for Spaces"
  value       = length(digitalocean_spaces_key.elasticsearch) > 0 ? digitalocean_spaces_key.elasticsearch[0].access_key : "Not configured - add Spaces credentials to enable"
  sensitive   = true
}

output "spaces_secret_key" {
  description = "Secret access key for Spaces"
  value       = length(digitalocean_spaces_key.elasticsearch) > 0 ? digitalocean_spaces_key.elasticsearch[0].secret_key : "Not configured - add Spaces credentials to enable"
  sensitive   = true
}

output "ssh_commands" {
  description = "SSH commands to connect to all Elasticsearch nodes (use esadmin user)"
  value = {
    for k, node in digitalocean_droplet.elasticsearch_nodes :
    k => "ssh esadmin@${node.ipv4_address}"
  }
}

output "security_notes" {
  description = "Important security configuration notes"
  value = <<-EOT
    === DEMO CLUSTER CONFIGURATION ===

    Cluster Access:
    - NO LOAD BALANCER: Connect directly to any node
    - Elasticsearch handles load balancing internally
    - Master-eligible nodes act as coordinators and route requests

    Authentication:
    - Username: elastic (superuser - use for all access in this demo)
    - Password: Run 'terraform output -raw elasticsearch_password_command' to get retrieval command
    - Or directly: ssh root@<first-es-node-ip> cat /root/.elastic_password

    Security Features Enabled:
    - TLS/SSL on all connections
    - X-Pack security with authentication
    - SSH root access disabled
    - Certificate-based node authentication

    Elasticsearch URLs:
    ${join("\n    ", [for k, node in digitalocean_droplet.elasticsearch_nodes : "- https://${node.ipv4_address}:9200"])}

    Next Steps:
    1. Access Kibana (see kibana_url output)
    2. SSH to nodes using: ssh esadmin@<node-ip>

    Note: This is a simplified demo setup with one superuser account.
    WARNING: Root SSH access is disabled. Use 'esadmin' user.
  EOT
}

# Kibana, EPR, and Artifact Registry Outputs
output "kibana_url" {
  description = "URL to access Kibana web interface"
  value       = "http://${digitalocean_droplet.kibana.ipv4_address}:5601"
}

output "kibana_ip" {
  description = "IP address of Kibana server"
  value       = digitalocean_droplet.kibana.ipv4_address
}

output "epr_url" {
  description = "Internal URL for Elastic Package Registry (air-gapped mode only)"
  value       = var.deployment_mode == "airgapped" ? "http://${digitalocean_droplet.epr[0].ipv4_address_private}:8443" : "Using public Elastic Package Registry (https://epr.elastic.co)"
}

output "epr_ip" {
  description = "IP address of EPR server (air-gapped mode only)"
  value       = var.deployment_mode == "airgapped" ? digitalocean_droplet.epr[0].ipv4_address : "N/A (networked mode)"
}

output "artifact_registry_url" {
  description = "Internal URL for Artifact Registry (air-gapped mode only)"
  value       = var.deployment_mode == "airgapped" ? "http://${digitalocean_droplet.artifact_registry[0].ipv4_address_private}:9080" : "Using public Elastic artifact repository"
}

output "artifact_registry_ip" {
  description = "IP address of Artifact Registry server (air-gapped mode only)"
  value       = var.deployment_mode == "airgapped" ? digitalocean_droplet.artifact_registry[0].ipv4_address : "N/A (networked mode)"
}

output "elastic_services_notes" {
  description = "Kibana, EPR, and Artifact Registry configuration notes"
  value = <<-EOT
===== ELASTIC SERVICES CONFIGURATION =====

Deployment Mode: ${var.deployment_mode == "airgapped" ? "Air-Gapped" : "Networked"}

1. Kibana Access:
   URL: http://${digitalocean_droplet.kibana.ipv4_address}:5601
   Username: elastic
   Password: ssh root@${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address} cat /root/.elastic_password

2. Configure Fleet (after Kibana starts):
   ssh esadmin@${digitalocean_droplet.kibana.ipv4_address}
   ./configure_fleet.sh <elastic_password>

${var.deployment_mode == "airgapped" ? "3. EPR (Internal Only):\n   URL: http://${digitalocean_droplet.epr[0].ipv4_address_private}:8443\n   Health: http://${digitalocean_droplet.epr[0].ipv4_address_private}:8443/health\n\n4. Artifact Registry (Internal Only):\n   URL: http://${digitalocean_droplet.artifact_registry[0].ipv4_address_private}:9080\n   Used by Fleet for agent binaries\n\n5. Add Artifacts:\n   ssh esadmin@${digitalocean_droplet.artifact_registry[0].ipv4_address}\n   See: ~/README_ARTIFACTS.md" : "3. Package Registry:\n   Uses public Elastic Package Registry: https://epr.elastic.co\n   No local EPR server needed\n\n4. Agent Artifacts:\n   Elastic Agents download binaries from public repositories\n   No local artifact registry needed\n\nNote: This deployment requires internet connectivity for:\n- Downloading Elastic packages during installation\n- Fleet Package Registry access\n- Elastic Agent binary downloads"}

========================================================
EOT
}

# Data Source Outputs - Cribl Stream
output "cribl_stream_urls" {
  description = "URLs to access Cribl Stream UI"
  value       = local.actual_cribl_count > 0 ? [for node in digitalocean_droplet.cribl_stream : "http://${node.ipv4_address}:9000"] : []
}

output "cribl_stream_ips" {
  description = "IP addresses of Cribl Stream nodes"
  value = local.actual_cribl_count > 0 ? {
    public  = digitalocean_droplet.cribl_stream[*].ipv4_address
    private = digitalocean_droplet.cribl_stream[*].ipv4_address_private
  } : {}
}

output "cribl_stream_ssh_commands" {
  description = "SSH commands to connect to Cribl Stream nodes (use cribladmin user)"
  value       = local.actual_cribl_count > 0 ? [for i, ip in digitalocean_droplet.cribl_stream[*].ipv4_address : "ssh cribladmin@${ip}"] : []
}

output "cribl_stream_notes" {
  description = "Cribl Stream configuration notes"
  value = local.actual_cribl_count > 0 ? join("", [
    "===== CRIBL STREAM CONFIGURATION =====\n\n",
    "Deployed: ${local.actual_cribl_count} Cribl Stream node(s)\n",
    "Mode: ${var.cribl_leader_mode}\n\n",
    "1. Access Cribl UI:\n   ",
    join("\n   ", [for i, node in digitalocean_droplet.cribl_stream : "Node ${i + 1}: http://${node.ipv4_address}:9000"]),
    "\n\n2. Get Credentials (Standalone mode):\n   ",
    join("\n   ", [for i, ip in digitalocean_droplet.cribl_stream[*].ipv4_address : "ssh cribladmin@${ip} && cat ~/cribl_credentials.txt"]),
    "\n\n3. Configure Elasticsearch Destination:\n",
    "   ssh cribladmin@<cribl-ip>\n",
    "   ./configure_elasticsearch_destination.sh <admin_password>\n\n",
    "4. Data Input Ports:\n",
    "   - Syslog TCP/UDP: 514\n",
    "   - HEC (HTTP Event Collector): 8088\n",
    "   - Raw TCP: 10001\n",
    "   - S3: 10200 (internal)\n\n",
    "5. Elasticsearch Connection:\n",
    "   - Destination URL: ${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address_private}:9200\n",
    "   - Username: elastic\n",
    "   - Password: ssh root@${values(digitalocean_droplet.elasticsearch_nodes)[0].ipv4_address} cat /root/.elastic_password\n\n",
    "Note: Configure routes and pipelines via Cribl UI\n",
    "SSH access restricted to cribladmin user\n\n",
    "======================================"
  ]) : "No Cribl Stream nodes deployed (set data_source_type='cribl' to enable)"
}
