# Elasticsearch Cluster on DigitalOcean

Terraform configuration for deploying a flexible, production-ready Elasticsearch cluster on DigitalOcean with configurable node count, optional data tiers, and searchable snapshot repository.

## Deployment Modes

This project supports **two deployment modes** that demonstrate different Fleet/integration architectures:

### 1. Networked Mode (Default)
- **Use when**: Standard deployment with public Elastic infrastructure
- **How it works**: Fleet uses public Elastic services
  - Package Registry: `epr.elastic.co` (for integrations)
  - Artifact Downloads: `artifacts.elastic.co` (for agent binaries)
- **Components**: Elasticsearch nodes (configurable) + Kibana
- **Installation**: All packages installed from internet during deployment

### 2. Local Package Registry Mode
- **Use when**: Demonstrating air-gapped/isolated architecture patterns
- **How it works**: Fleet uses local infrastructure instead of public Elastic services
  - **Local EPR** (Elastic Package Registry): Serves integration packages locally
  - **Local Artifact Registry**: Serves Elastic Agent binaries locally
  - Fleet automatically configured to use these local registries
- **Components**: Elasticsearch + Kibana + Local EPR + Local Artifact Registry
- **Installation**: All packages installed from internet during deployment
- **Key Difference**: Fleet configuration points to local registries instead of public ones

**Important**: Both modes use internet connectivity during installation. The "local package registry" mode demonstrates how to configure Fleet for air-gapped operations by using local registries, but installation itself requires internet access.

**Switch modes** by setting `deployment_mode = "airgapped"` in `terraform.tfvars`

## Architecture

### Infrastructure (Flexible Configuration)
- **Hot Nodes**: 1-10 nodes (configurable, default: 1) - master-eligible, data_hot, ingest roles, also act as coordinators
- **Cold Tier**: Optional 1 node with 2GB RAM (data_cold role only, disabled by default)
- **Frozen Tier**: Optional 1 node with 2GB RAM (data_frozen role only, disabled by default)
- **Kibana**: Always included for cluster management and visualization
- **DigitalOcean Spaces**: S3-compatible storage for searchable snapshots (auto-created when cold/frozen tiers enabled)
- **No Load Balancer**: Elasticsearch handles load balancing internally via coordinator nodes
- **VPC**: Private network isolation for secure cluster communication
- **Optional Data Sources**: Cribl Stream VMs for data routing and processing (disabled by default)

### Security Features (Enterprise-Grade)
- **Certificate Authority**: Centralized CA with proper certificate chain
- **TLS/SSL Everywhere**: Transport and HTTP layers fully encrypted
- **RBAC**: Multiple user levels (superuser, admin, monitor, ingest)
- **API Keys**: Automatic generation for programmatic access
- **Audit Logging**: Comprehensive security event tracking
- **Firewall Rules**: Restrictive rules following zero-trust principles
- **SSH Hardening**: Root disabled, non-root esadmin user only
- **Keystore**: Sensitive data protection

## Deployment Process

### Both Modes - Installation Phase
Both deployment modes follow the same installation process:

1. **Deployment Phase**: Terraform creates droplets
2. **Installation Phase**: Droplets download and install packages from internet:
   - Elasticsearch from Elastic repositories
   - Kibana from Elastic repositories
   - Docker (for EPR container, if local registry mode)
   - Nginx (for Artifact Registry, if local registry mode)
   - All system dependencies
3. **Security Configuration**: Certificate setup, user creation, firewall rules

### Local Package Registry Mode - Additional Configuration

After installation, the local package registry mode performs additional steps:

4. **Deploy Local Registries**:
   - **EPR Container**: Runs Elastic Package Registry on port 8443
   - **Artifact Registry**: Configures Nginx to serve agent binaries on port 9080

5. **Configure Fleet** (Automatic via API):
   - Sets Package Registry URL to `http://10.10.10.2:8443` (local EPR)
   - Sets Agent Binary Downloads to `http://10.10.10.3:9080/downloads/` (local Artifact Registry)

6. **Result**: Fleet now uses local infrastructure instead of public Elastic services

### Demonstrating Air-Gapped Capability

While installation uses internet access, the local registry mode demonstrates air-gapped patterns:
- Integrations fetched from local EPR instead of epr.elastic.co
- Agent binaries downloaded from local Artifact Registry instead of artifacts.elastic.co
- Optional: Block outbound traffic to Elastic's public servers to prove independence

## Prerequisites

### Required (Both Modes)

1. DigitalOcean account with API token
2. SSH key added to DigitalOcean account
3. Terraform >= 1.0
4. DigitalOcean CLI (optional, for verification)
5. Droplets need internet access (HTTP/HTTPS outbound) during installation

### No Additional Requirements

Both deployment modes use the same installation process. The local package registry mode simply adds configuration steps after installation to set up and configure the local registries.

## Setup Instructions

### 1. Configure Environment

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
- `deployment_mode`: Set to "airgapped" or "networked" (default: "networked")
  - "networked": Fleet uses public Elastic services (epr.elastic.co, artifacts.elastic.co)
  - "airgapped": Fleet uses local registries (demonstrates air-gapped architecture)
- `ssh_key_name`: Name of your SSH key in DigitalOcean (REQUIRED)
- `allowed_ips`: IPs allowed to access Elasticsearch API (RESTRICT IN PRODUCTION)
- `allowed_ssh_ips`: IPs allowed SSH access (leave empty to use allowed_ips)
- `region`: Choose your preferred DigitalOcean region

**Object Storage (DigitalOcean Spaces) - Auto-Created When Needed:**

Spaces (S3-compatible object storage) is **automatically created** when you enable cold or frozen tiers:
- **Required for**: Frozen tier (uses searchable snapshots stored in Spaces)
- **Useful for**: Cold tier (for backups and snapshot repository)
- **Not needed for**: Hot nodes only deployments

To enable Spaces, add these to `terraform.tfvars`:
```hcl
spaces_access_id     = "your-spaces-access-key"
spaces_secret_key    = "your-spaces-secret-key"
```

**Important**: If you enable `enable_frozen_tier=true`, you MUST provide Spaces credentials. The deployment will fail without them.

### 4. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

**Flexible Deployment Examples:**

You can customize your deployment using command-line variables. Here are common configurations:

```bash
# Minimal demo: 1 hot node, networked mode (cheapest)
terraform apply -var="deployment_mode=normal" -var="hot_node_count=1"

# Single node with Cribl data source
terraform apply -var="hot_node_count=1" -var="data_source_type=cribl" -var="data_source_count=1"

# Production-like: 3 hot nodes + cold/frozen tiers (requires Spaces credentials in terraform.tfvars)
terraform apply -var="hot_node_count=3" -var="enable_cold_tier=true" -var="enable_frozen_tier=true"

# Custom: 2 hot nodes, no tiers, networked mode
terraform apply -var="deployment_mode=normal" -var="hot_node_count=2" -var="enable_cold_tier=false" -var="enable_frozen_tier=false"
```

The default configuration (if no variables specified) deploys 1 hot node + Kibana in networked mode with no cold/frozen tiers.

**What happens during deployment:**

**Air-Gapped Mode:**
1. **Droplet Creation**: Creates ES nodes + Kibana + EPR + Artifact Registry with VPC networking
2. **Package Upload**: Terraform automatically uploads all packages via SSH
3. **Local Installation**: Each droplet installs from local packages without internet access
4. **Security Configuration**: Sets up TLS, RBAC, certificates, and audit logging
5. **Cluster Formation**: Nodes discover each other and form a secure cluster
   - Deployment time: ~15-20 minutes (including package upload)

**Networked Mode:**
1. **Droplet Creation**: Creates ES nodes + Kibana with VPC networking (tiers/count based on your variables)
2. **Internet Installation**: Droplets download packages from Elastic repositories
3. **Security Configuration**: Sets up TLS, RBAC, certificates, and audit logging
4. **Cluster Formation**: Nodes discover each other and form a secure cluster
   - Deployment time: ~10-15 minutes (faster, no upload required)

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

## Optional: Data Source VMs

### Cribl Stream

This project supports optional **Cribl Stream** VMs for advanced data routing, processing, and transformation before sending to Elasticsearch.

#### What is Cribl Stream?

Cribl Stream is a vendor-agnostic observability pipeline that allows you to:
- Collect data from multiple sources (syslog, HEC, S3, etc.)
- Route data to multiple destinations
- Transform, enrich, and filter data in-flight
- Reduce data volume and costs
- Mask sensitive information (PII/PCI)

#### Enable Cribl Stream

Edit `terraform.tfvars`:
```bash
# Enable Cribl Stream
cribl_stream_count = 1  # Create 1 Cribl Stream instance

# Optional configuration:
cribl_stream_node_size = "s-2vcpu-4gb"  # Recommended minimum
cribl_stream_version   = "4.8.2"        # Version to install
cribl_leader_mode      = "standalone"   # or "worker" for distributed mode
```

Then deploy:
```bash
terraform apply
```

#### Configure Cribl Stream

After deployment:

1. **Get Credentials** (Standalone mode):
   ```bash
   ssh cribladmin@<cribl-ip>
   cat ~/cribl_credentials.txt
   ```

2. **Access Cribl UI**:
   - URL: `http://<cribl-ip>:9000`
   - Login with credentials from step 1

3. **Configure Elasticsearch Destination**:
   ```bash
   ssh cribladmin@<cribl-ip>
   ./configure_elasticsearch_destination.sh <admin_password>
   ```

4. **Configure Data Sources**:
   - In Cribl UI, go to **Sources** → **Add Source**
   - Available ports:
     - **Syslog**: TCP/UDP 514
     - **HEC** (HTTP Event Collector): TCP 8088
     - **Raw TCP**: TCP 10001
     - **S3**: TCP 10200 (internal)

5. **Create Routes & Pipelines**:
   - Go to **Routes** to define data flows
   - Use **Pipelines** to transform data
   - Reference: [Cribl Documentation](https://docs.cribl.io/)

#### Worker Mode (Distributed Deployment)

For distributed deployments with an external Cribl Leader:

```bash
cribl_stream_count = 3  # Create 3 workers
cribl_leader_mode  = "worker"
cribl_leader_url   = "https://your-leader:4200"
cribl_auth_token   = "your-worker-auth-token"
```

Workers will automatically connect to the leader for centralized management.

#### Deployment Modes

Cribl Stream respects the `deployment_mode` variable:
- **Air-gapped**: Cribl packages pre-downloaded and uploaded
- **Networked**: Installed from Cribl repositories

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

### Base Deployment (Elasticsearch + Kibana)

Monthly costs (approximate):
- 3x Hot nodes (8GB): $48/month each = $144
- 1x Cold node (2GB): $12/month
- 1x Frozen node (2GB): $12/month
- 1x Kibana (2GB): $12/month
- Spaces storage: Variable based on usage
- **Total**: ~$180/month + storage

### Air-Gapped Mode Additional Costs

- 1x EPR (2GB): $12/month
- 1x Artifact Registry (2GB): $12/month
- **Additional Total**: ~$24/month

### Optional Data Sources

- **Cribl Stream** (per instance): $24/month (s-2vcpu-4gb)
  - Example: 1 Cribl instance = +$24/month
  - Example: 3 Cribl workers = +$72/month

### Total Cost Examples

1. **Networked Mode** (minimal): ~$180/month
2. **Air-Gapped Mode**: ~$204/month
3. **Networked + 1 Cribl**: ~$204/month
4. **Air-Gapped + 1 Cribl**: ~$228/month

**Note**: No load balancer cost - Elasticsearch handles load balancing internally

## Important Notes

### Deployment Modes

**Air-Gapped Mode:**
- Droplets have NO internet access during installation
- All packages pre-downloaded and uploaded via Terraform
- Includes EPR and Artifact Registry for Fleet
- Package upload requires SSH access to droplets
- Full isolation for maximum security

**Networked Mode:**
- Droplets require HTTP/HTTPS outbound access
- Packages installed directly from Elastic repositories
- Uses public EPR and artifact repositories
- Faster deployment, simpler setup
- No package download or upload required

### Components by Mode

**Air-Gapped Mode Components:**
- 5-node Elasticsearch cluster (3 hot, 1 cold, 1 frozen)
- Kibana web interface
- Elastic Package Registry (EPR) - local server
- Artifact Registry - local server for Fleet/Agent binaries
- All components fully isolated from internet

**Networked Mode Components:**
- 5-node Elasticsearch cluster (3 hot, 1 cold, 1 frozen)
- Kibana web interface
- Uses public Elastic Package Registry (https://epr.elastic.co)
- Uses public Elastic artifact repositories

### Security
- Self-signed certificates are used; replace with CA-signed for production
- SSH root access is disabled; use `esadmin` user
- Firewall rules follow zero-trust/least-privilege principles
- Regular password and API key rotation recommended
- Both modes provide same security features (TLS, RBAC, audit logging)

### Backups
- Regular snapshots to DigitalOcean Spaces recommended
- Test restore procedures regularly
- Consider additional backup strategies beyond snapshot repository