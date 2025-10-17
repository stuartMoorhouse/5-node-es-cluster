output "cluster_name" {
  description = "Name of the Elasticsearch cluster"
  value       = local.cluster_name_prefix
}

output "elasticsearch_urls" {
  description = "URLs to access Elasticsearch cluster (connect to any hot node)"
  value       = [for node in digitalocean_droplet.hot_nodes : "https://${node.ipv4_address}:9200"]
}

output "primary_elasticsearch_url" {
  description = "Primary URL for Elasticsearch access (first hot node)"
  value       = "https://${digitalocean_droplet.hot_nodes[0].ipv4_address}:9200"
}

output "elasticsearch_password" {
  description = "Elasticsearch elastic user password (superuser)"
  value       = random_password.elastic_password.result
  sensitive   = true
}

output "monitor_password" {
  description = "Monitoring user password (read-only access)"
  value       = random_password.monitor_password.result
  sensitive   = true
}

output "ingest_password" {
  description = "Ingest user password (write access to logs/metrics)"
  value       = random_password.ingest_password.result
  sensitive   = true
}

output "admin_password" {
  description = "Admin user password (cluster admin, not superuser)"
  value       = random_password.admin_password.result
  sensitive   = true
}

output "hot_node_ips" {
  description = "IP addresses of hot nodes"
  value = {
    public  = digitalocean_droplet.hot_nodes[*].ipv4_address
    private = digitalocean_droplet.hot_nodes[*].ipv4_address_private
  }
}

output "cold_node_ip" {
  description = "IP address of cold node"
  value = {
    public  = digitalocean_droplet.cold_node.ipv4_address
    private = digitalocean_droplet.cold_node.ipv4_address_private
  }
}

output "frozen_node_ip" {
  description = "IP address of frozen node"
  value = {
    public  = digitalocean_droplet.frozen_node.ipv4_address
    private = digitalocean_droplet.frozen_node.ipv4_address_private
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

output "ssh_command_hot_nodes" {
  description = "SSH commands to connect to hot nodes (use esadmin user)"
  value       = [for i, ip in digitalocean_droplet.hot_nodes[*].ipv4_address : "ssh esadmin@${ip}"]
}

output "ssh_command_cold_node" {
  description = "SSH command to connect to cold node (use esadmin user)"
  value       = "ssh esadmin@${digitalocean_droplet.cold_node.ipv4_address}"
}

output "ssh_command_frozen_node" {
  description = "SSH command to connect to frozen node (use esadmin user)"
  value       = "ssh esadmin@${digitalocean_droplet.frozen_node.ipv4_address}"
}

output "security_notes" {
  description = "Important security configuration notes"
  value = <<-EOT
    === SECURITY CONFIGURATION COMPLETE ===

    Cluster Access:
    - NO LOAD BALANCER: Connect directly to any hot node
    - Elasticsearch handles load balancing internally
    - Hot nodes act as coordinators and route requests
    - Configure clients with multiple node URLs for HA

    Users Created:
    - elastic: Superuser (use sparingly)
    - admin: Cluster administrator
    - monitor: Read-only monitoring
    - ingest: Data ingestion only

    Security Features Enabled:
    - TLS/SSL on all connections
    - X-Pack security with authentication
    - Audit logging enabled
    - RBAC with least privilege principle
    - SSH root access disabled
    - Restrictive firewall rules
    - Certificate-based node authentication

    Client Configuration:
    Configure your Elasticsearch clients with all hot node URLs:
    ${join("\n    ", [for node in digitalocean_droplet.hot_nodes : "- https://${node.ipv4_address}:9200"])}

    Next Steps:
    1. Retrieve passwords with: terraform output -raw <user>_password
    2. SSH to nodes using: ssh esadmin@<node-ip>
    3. Configure snapshot repository using the script on any node
    4. API keys are stored in /home/esadmin/api_keys.txt on first node
    5. Validate security with: /home/esadmin/validate_security.sh

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
  value = var.deployment_mode == "airgapped" ? <<-EOT
    ===== ELASTIC SERVICES CONFIGURATION (AIR-GAPPED) =====

    Deployment Mode: Air-Gapped

    1. Kibana Access:
       URL: http://${digitalocean_droplet.kibana.ipv4_address}:5601
       Username: elastic
       Password: <use elasticsearch_password output>

    2. Configure Fleet (after Kibana starts):
       ssh esadmin@${digitalocean_droplet.kibana.ipv4_address}
       ./configure_fleet.sh <elastic_password>

    3. EPR (Internal Only):
       URL: http://${digitalocean_droplet.epr[0].ipv4_address_private}:8443
       Health: http://${digitalocean_droplet.epr[0].ipv4_address_private}:8443/health

    4. Artifact Registry (Internal Only):
       URL: http://${digitalocean_droplet.artifact_registry[0].ipv4_address_private}:9080
       Used by Fleet for agent binaries

    5. Add Artifacts:
       ssh esadmin@${digitalocean_droplet.artifact_registry[0].ipv4_address}
       See: ~/README_ARTIFACTS.md

    ========================================================
  EOT
  : <<-EOT
    ===== ELASTIC SERVICES CONFIGURATION (NETWORKED) =====

    Deployment Mode: Networked

    1. Kibana Access:
       URL: http://${digitalocean_droplet.kibana.ipv4_address}:5601
       Username: elastic
       Password: <use elasticsearch_password output>

    2. Configure Fleet (after Kibana starts):
       ssh esadmin@${digitalocean_droplet.kibana.ipv4_address}
       ./configure_fleet.sh <elastic_password>

    3. Package Registry:
       Uses public Elastic Package Registry: https://epr.elastic.co
       No local EPR server needed

    4. Agent Artifacts:
       Elastic Agents download binaries from public repositories
       No local artifact registry needed

    Note: This deployment requires internet connectivity for:
    - Downloading Elastic packages during installation
    - Fleet Package Registry access
    - Elastic Agent binary downloads

    ======================================================
  EOT
}

# Data Source Outputs - Cribl Stream
output "cribl_stream_urls" {
  description = "URLs to access Cribl Stream UI"
  value       = var.cribl_stream_count > 0 ? [for node in digitalocean_droplet.cribl_stream : "http://${node.ipv4_address}:9000"] : []
}

output "cribl_stream_ips" {
  description = "IP addresses of Cribl Stream nodes"
  value = var.cribl_stream_count > 0 ? {
    public  = digitalocean_droplet.cribl_stream[*].ipv4_address
    private = digitalocean_droplet.cribl_stream[*].ipv4_address_private
  } : {}
}

output "cribl_stream_ssh_commands" {
  description = "SSH commands to connect to Cribl Stream nodes (use cribladmin user)"
  value       = var.cribl_stream_count > 0 ? [for i, ip in digitalocean_droplet.cribl_stream[*].ipv4_address : "ssh cribladmin@${ip}"] : []
}

output "cribl_stream_notes" {
  description = "Cribl Stream configuration notes"
  value = var.cribl_stream_count > 0 ? <<-EOT
    ===== CRIBL STREAM CONFIGURATION =====

    Deployed: ${var.cribl_stream_count} Cribl Stream node(s)
    Mode: ${var.cribl_leader_mode}

    1. Access Cribl UI:
       ${join("\n       ", [for i, node in digitalocean_droplet.cribl_stream : "Node ${i + 1}: http://${node.ipv4_address}:9000"])}

    2. Get Credentials (Standalone mode):
       ${join("\n       ", [for i, ip in digitalocean_droplet.cribl_stream[*].ipv4_address : "ssh cribladmin@${ip} && cat ~/cribl_credentials.txt"])}

    3. Configure Elasticsearch Destination:
       ssh cribladmin@<cribl-ip>
       ./configure_elasticsearch_destination.sh <admin_password>

    4. Data Input Ports:
       - Syslog TCP/UDP: 514
       - HEC (HTTP Event Collector): 8088
       - Raw TCP: 10001
       - S3: 10200 (internal)

    5. Elasticsearch Connection:
       - Destination URL: ${digitalocean_droplet.hot_nodes[0].ipv4_address_private}:9200
       - Username: ingest
       - Password: <use ingest_password output>

    Note: Configure routes and pipelines via Cribl UI
    SSH access restricted to cribladmin user

    ======================================
  EOT
  : "No Cribl Stream nodes deployed (set cribl_stream_count > 0 to enable)"
}
