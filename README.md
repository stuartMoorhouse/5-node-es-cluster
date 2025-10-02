# 5-Node Elasticsearch Cluster on DigitalOcean

Terraform configuration for deploying a production-ready Elasticsearch cluster on DigitalOcean with hot, cold, and frozen data tiers plus searchable snapshot repository.

## Architecture

- **3 Hot Nodes**: 8GB RAM droplets for active data and queries
- **1 Cold Node**: 2GB RAM droplet for less frequently accessed data
- **1 Frozen Node**: 2GB RAM droplet for rarely accessed data
- **DigitalOcean Spaces**: S3-compatible storage for searchable snapshots
- **Load Balancer**: For distributing client requests
- **VPC**: Private network isolation for cluster communication
- **Firewall**: Configured security rules following zero-trust principles

## Prerequisites

1. DigitalOcean account with API token
2. SSH key added to DigitalOcean account
3. Terraform >= 1.0
4. DigitalOcean CLI (optional, for verification)

## Setup Instructions

### 1. Configure Environment

```bash
# Set your DigitalOcean API token
export DIGITALOCEAN_TOKEN="your-digitalocean-api-token"
```

### 2. Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
- `ssh_key_name`: Name of your SSH key in DigitalOcean (REQUIRED)
- `allowed_ips`: Restrict to your IP addresses for security
- `region`: Choose your preferred DigitalOcean region

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

Deployment takes approximately 10-15 minutes.

### 4. Retrieve Cluster Credentials

```bash
# Get the Elasticsearch URL
terraform output elasticsearch_url

# Get the elastic user password (sensitive)
terraform output -raw elasticsearch_password

# Get Spaces credentials for snapshot repository
terraform output -raw spaces_access_key
terraform output -raw spaces_secret_key
```

### 5. Verify Cluster Health

```bash
# Get load balancer IP
LB_IP=$(terraform output -raw load_balancer_ip)

# Check cluster health (using the elastic password from output)
curl -k -u elastic:$(terraform output -raw elasticsearch_password) \
  https://$LB_IP:9200/_cluster/health?pretty
```

## Post-Deployment Configuration

### Configure Searchable Snapshot Repository

SSH into one of the nodes and run the configuration script:

```bash
# SSH into a hot node
ssh root@<node-ip>

# Configure the snapshot repository
./configure_snapshot_repo.sh \
  <spaces_endpoint> \
  <access_key> \
  <secret_key>
```

### Configure Index Lifecycle Management (ILM)

Create an ILM policy for data tiering:

```bash
curl -k -u elastic:<password> -X PUT "https://<lb-ip>:9200/_ilm/policy/data-tiering" \
  -H "Content-Type: application/json" \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "actions": {
            "rollover": {
              "max_age": "7d",
              "max_size": "50GB"
            }
          }
        },
        "warm": {
          "min_age": "7d",
          "actions": {
            "shrink": {
              "number_of_shards": 1
            },
            "forcemerge": {
              "max_num_segments": 1
            }
          }
        },
        "cold": {
          "min_age": "30d",
          "actions": {
            "searchable_snapshot": {
              "snapshot_repository": "searchable_snapshots"
            }
          }
        },
        "frozen": {
          "min_age": "90d",
          "actions": {
            "searchable_snapshot": {
              "snapshot_repository": "searchable_snapshots",
              "storage": "shared_cache"
            }
          }
        }
      }
    }
  }'
```

## Security Considerations

1. **TLS/SSL**: All nodes use self-signed certificates. For production, use proper CA-signed certificates.
2. **Firewall Rules**: By default, access is restricted. Update `allowed_ips` in terraform.tfvars.
3. **Authentication**: X-Pack security is enabled with username/password authentication.
4. **Network Isolation**: Nodes communicate over private VPC network.
5. **Principle of Least Privilege**: Each component has minimal required permissions.

## Maintenance

### Scaling the Cluster

To add more hot nodes, update `hot_node_count` in terraform.tfvars and run:
```bash
terraform apply
```

### Updating Elasticsearch

To upgrade Elasticsearch version:
1. Update `elasticsearch_version` in terraform.tfvars
2. Plan a maintenance window
3. Apply changes with rolling updates

### Destroying the Cluster

```bash
terraform destroy
```

**WARNING**: This will delete all data and snapshots.

## Troubleshooting

### Connection Issues
- Verify firewall rules allow your IP
- Check node status via SSH
- Review Elasticsearch logs: `journalctl -u elasticsearch`

### Cluster Formation Issues
- Ensure all nodes can reach each other on port 9300
- Verify discovery settings in elasticsearch.yml
- Check cluster formation logs

### Snapshot Repository Issues
- Verify Spaces credentials are correct
- Check bucket permissions
- Test S3 connectivity from nodes

## Cost Estimation

Monthly costs (approximate):
- 3x Hot nodes (8GB): $48/month each = $144
- 1x Cold node (2GB): $12/month
- 1x Frozen node (2GB): $12/month
- Load Balancer: $12/month
- Spaces storage: Variable based on usage
- **Total**: ~$180/month + storage

## Important Notes

- This configuration uses Elasticsearch 9.2.0 as requested
- Self-signed certificates are used; replace with CA-signed for production
- Regular backups are recommended beyond snapshot repository