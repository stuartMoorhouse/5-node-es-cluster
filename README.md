# 5-Node Elasticsearch Cluster on DigitalOcean (Air-Gapped)

Terraform configuration for deploying a production-ready, **air-gapped** Elasticsearch cluster on DigitalOcean with hot, cold, and frozen data tiers plus searchable snapshot repository.

**Key Feature**: This deployment is fully air-gapped - droplets do not require internet access during installation. All packages are pre-downloaded and uploaded via Terraform.

## Architecture

### Infrastructure
- **3 Hot Nodes**: 8GB RAM droplets (master-eligible, data_hot, ingest roles) - Also act as coordinators
- **1 Cold Node**: 2GB RAM droplet (data_cold role only)
- **1 Frozen Node**: 2GB RAM droplet (data_frozen role only)
- **DigitalOcean Spaces**: S3-compatible storage for searchable snapshots
- **No Load Balancer**: Elasticsearch handles load balancing internally via coordinator nodes
- **VPC**: Private network isolation for secure cluster communication

### Security Features (Enterprise-Grade)
- **Certificate Authority**: Centralized CA with proper certificate chain
- **TLS/SSL Everywhere**: Transport and HTTP layers fully encrypted
- **RBAC**: Multiple user levels (superuser, admin, monitor, ingest)
- **API Keys**: Automatic generation for programmatic access
- **Audit Logging**: Comprehensive security event tracking
- **Firewall Rules**: Restrictive rules following zero-trust principles
- **SSH Hardening**: Root disabled, non-root esadmin user only
- **Keystore**: Sensitive data protection

## Air-Gapped Deployment Overview

This configuration deploys Elasticsearch in an **air-gapped environment** where droplets have no internet access during installation. The deployment process:

1. **Preparation Phase** (Internet-connected machine): Download all required packages
2. **Upload Phase** (Terraform): Automatically upload packages to droplets
3. **Installation Phase** (Droplets): Install from local packages without internet access

## Prerequisites

### Required

1. DigitalOcean account with API token
2. SSH key added to DigitalOcean account (for provisioning)
3. SSH private key file locally (for package upload)
4. Terraform >= 1.0
5. **Internet connection on your local machine** (to download packages)

### Optional

- Docker (for automatic dependency download)
- DigitalOcean CLI (for verification)

## Setup Instructions

### 1. Download Required Packages (Air-Gapped Preparation)

**This step must be completed on an internet-connected machine before deployment.**

```bash
cd terraform/scripts

# Run the download script
./download_packages.sh
```

This script will:
- Download Elasticsearch 9.1.5 DEB package
- Attempt to download Java and dependencies using Docker (if available)
- Create instructions for manual download if Docker is unavailable
- Generate a manifest of downloaded packages

**Verify the download:**

```bash
# Check the manifest
cat ../packages/MANIFEST.md

# Verify Elasticsearch package
ls -lh ../packages/elasticsearch/

# Check Java packages (if Docker was available)
ls -lh ../packages/java/

# Check dependencies (if Docker was available)
ls -lh ../packages/dependencies/
```

**Manual Download (if Docker unavailable):**

If Docker is not available, follow the instructions in:
- `terraform/packages/java/README.md`
- `terraform/packages/dependencies/README.md`

### 2. Configure Environment

```bash
# Set your DigitalOcean API token
export DIGITALOCEAN_TOKEN="your-digitalocean-api-token"
```

### 3. Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
- `ssh_key_name`: Name of your SSH key in DigitalOcean (REQUIRED)
- `ssh_private_key_path`: Path to your SSH private key file (default: `~/.ssh/id_rsa`)
- `allowed_ips`: IPs allowed to access Elasticsearch API (RESTRICT IN PRODUCTION)
- `allowed_ssh_ips`: IPs allowed SSH access (leave empty to use allowed_ips)
- `region`: Choose your preferred DigitalOcean region

**Important**: The `ssh_private_key_path` is used by Terraform to upload packages to droplets.

### 4. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

**What happens during deployment:**

1. **Droplet Creation**: Creates 5 droplets (3 hot, 1 cold, 1 frozen) with VPC networking
2. **Package Upload**: Terraform automatically uploads all packages from `terraform/packages/` to each droplet via SSH
3. **Air-Gapped Installation**: Each droplet installs Elasticsearch from local packages without internet access
4. **Security Configuration**: Sets up TLS, RBAC, certificates, and audit logging
5. **Cluster Formation**: Nodes discover each other and form a secure cluster

Deployment takes approximately 15-20 minutes (including package upload time).

### 5. Retrieve Cluster Credentials

```bash
# Get the Elasticsearch URLs (all hot nodes)
terraform output elasticsearch_urls

# Get primary URL (for single-endpoint testing)
terraform output primary_elasticsearch_url

# Get user passwords (use specific users for different purposes)
terraform output -raw elasticsearch_password  # Superuser (use sparingly)
terraform output -raw admin_password         # Cluster admin
terraform output -raw monitor_password       # Read-only monitoring
terraform output -raw ingest_password        # Data ingestion only

# Get Spaces credentials for snapshot repository
terraform output -raw spaces_access_key
terraform output -raw spaces_secret_key

# Display security configuration notes
terraform output security_notes
```

### 6. Verify Cluster Health and Air-Gapped Installation

```bash
# Get first hot node IP for testing
NODE_IP=$(terraform output -json elasticsearch_urls | jq -r '.[0]' | sed 's|https://||' | sed 's|:9200||')

# Check cluster health (using the elastic password from output)
curl -k -u elastic:$(terraform output -raw elasticsearch_password) \
  https://$NODE_IP:9200/_cluster/health?pretty

# Or use the primary URL directly
curl -k -u elastic:$(terraform output -raw elasticsearch_password) \
  $(terraform output -raw primary_elasticsearch_url)/_cluster/health?pretty
```

**Verify Air-Gapped Installation:**

SSH into any node to confirm installation was air-gapped:

```bash
# SSH to a node
ssh esadmin@$NODE_IP

# Check installation was from local packages (should show installed from local file)
dpkg -l | grep elasticsearch

# Verify no outbound internet connections were made during installation
# (This would require firewall logging to be enabled)
sudo journalctl -u elasticsearch | grep -i "download\|internet\|http" || echo "No internet access detected"

# Exit
exit
```

## Post-Deployment Configuration

### Configure Client Applications

Since there's no load balancer, configure your Elasticsearch clients to connect to multiple hot nodes for high availability:

#### Python Client Example
```python
from elasticsearch import Elasticsearch

# Get all hot node URLs from Terraform output
es = Elasticsearch(
    ['https://node1:9200', 'https://node2:9200', 'https://node3:9200'],
    basic_auth=('elastic', 'your-password'),
    verify_certs=False  # Use True with proper CA in production
)
```

#### JavaScript Client Example
```javascript
const { Client } = require('@elastic/elasticsearch')

const client = new Client({
  nodes: [
    'https://node1:9200',
    'https://node2:9200',
    'https://node3:9200'
  ],
  auth: {
    username: 'elastic',
    password: 'your-password'
  },
  tls: {
    rejectUnauthorized: false  // Use true with proper CA in production
  }
})
```

#### Logstash Configuration
```ruby
output {
  elasticsearch {
    hosts => ["node1:9200", "node2:9200", "node3:9200"]
    user => "ingest"
    password => "your-ingest-password"
    ssl => true
    ssl_certificate_verification => false  # Use true in production
  }
}
```

The Elasticsearch clients automatically handle:
- Load balancing across nodes
- Failover when a node is unavailable
- Connection pooling
- Request retries

### Configure Searchable Snapshot Repository

SSH into one of the nodes and run the configuration script:

```bash
# SSH into a hot node (as esadmin user, root is disabled)
ssh esadmin@<node-ip>

# Configure the snapshot repository
./configure_snapshot_repo.sh \
  <spaces_endpoint> \
  <access_key> \
  <secret_key>
```

### Validate Security Configuration

```bash
# SSH to any node
ssh esadmin@<node-ip>

# Run security validation script
./validate_security.sh $(terraform output -raw elasticsearch_password)

# Check API keys (on first hot node only)
cat /home/esadmin/api_keys.txt
```

### Configure Index Lifecycle Management (ILM)

Create an ILM policy for data tiering:

```bash
# Use any hot node IP
curl -k -u elastic:<password> -X PUT "https://<node-ip>:9200/_ilm/policy/data-tiering" \
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

### Implemented Security Controls

1. **Certificate Management**:
   - Centralized Certificate Authority (CA) with proper certificate chain
   - All nodes have CA-signed certificates
   - Full verification mode enabled

2. **Access Control**:
   - **RBAC**: Multiple user levels (elastic, admin, monitor, ingest)
   - **API Keys**: Generated automatically for programmatic access
   - **SSH**: Root disabled, esadmin user only with sudo privileges

3. **Network Security**:
   - **Firewall Rules**: Restrictive inbound/outbound rules
   - **VPC Isolation**: Private network for cluster communication
   - **Direct Node Access**: Clients connect directly to hot nodes (no load balancer needed)

4. **Audit & Compliance**:
   - **Audit Logging**: All security events logged
   - **Authentication Tracking**: Failed/successful logins recorded
   - **Keystore**: Sensitive data protected

### Security Best Practices

- Use the principle of least privilege - assign users minimum required roles
- Regularly rotate passwords and API keys
- Monitor audit logs for suspicious activity
- Restrict `allowed_ips` and `allowed_ssh_ips` to known IPs only
- Use separate API keys for different applications
- Avoid using elastic superuser for routine operations

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
- Spaces storage: Variable based on usage
- **Total**: ~$168/month + storage

**Note**: No load balancer cost - Elasticsearch handles load balancing internally

## Important Notes

### Air-Gapped Deployment
- **Droplets have NO internet access** during Elasticsearch installation
- All packages are pre-downloaded and uploaded via Terraform
- Elasticsearch version 9.1.5 (latest stable as of October 2025)
- Manual package download required if Docker is unavailable
- Package upload requires SSH access to droplets

### Security
- Self-signed certificates are used; replace with CA-signed for production
- SSH root access is disabled; use `esadmin` user
- Firewall rules follow zero-trust/least-privilege principles
- Regular password and API key rotation recommended

### Backups
- Regular snapshots to DigitalOcean Spaces recommended
- Test restore procedures regularly
- Consider additional backup strategies beyond snapshot repository

### Phase 2 (Optional - Not Yet Implemented)
This is Phase 1: Air-gapped Elasticsearch cluster only. Phase 2 would add:
- Kibana
- Elastic Package Registry (EPR)
- Artifact Registry for Fleet/Agent
- See `product-requirement-prompts.md` for Phase 2 details