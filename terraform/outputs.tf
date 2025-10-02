output "cluster_name" {
  description = "Name of the Elasticsearch cluster"
  value       = local.cluster_name_prefix
}

output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value       = digitalocean_loadbalancer.elasticsearch.ip
}

output "elasticsearch_url" {
  description = "URL to access Elasticsearch cluster"
  value       = "https://${digitalocean_loadbalancer.elasticsearch.ip}:9200"
}

output "elasticsearch_password" {
  description = "Elasticsearch elastic user password"
  value       = random_password.elastic_password.result
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
  value       = digitalocean_spaces_bucket.elasticsearch_snapshots.name
}

output "spaces_endpoint" {
  description = "Endpoint for the DigitalOcean Spaces bucket"
  value       = digitalocean_spaces_bucket.elasticsearch_snapshots.bucket_domain_name
}

output "spaces_access_key" {
  description = "Access key ID for Spaces"
  value       = digitalocean_spaces_bucket_access_key.elasticsearch.key
  sensitive   = true
}

output "spaces_secret_key" {
  description = "Secret access key for Spaces"
  value       = digitalocean_spaces_bucket_access_key.elasticsearch.secret
  sensitive   = true
}

output "ssh_command_hot_nodes" {
  description = "SSH commands to connect to hot nodes"
  value       = [for i, ip in digitalocean_droplet.hot_nodes[*].ipv4_address : "ssh root@${ip}"]
}

output "ssh_command_cold_node" {
  description = "SSH command to connect to cold node"
  value       = "ssh root@${digitalocean_droplet.cold_node.ipv4_address}"
}

output "ssh_command_frozen_node" {
  description = "SSH command to connect to frozen node"
  value       = "ssh root@${digitalocean_droplet.frozen_node.ipv4_address}"
}