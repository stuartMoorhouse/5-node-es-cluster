# Product Requirement Prompts


## Objective

```
# What is the main goal of this project? Be specific and concise
Create a Terraform configuration to host a small Elasticsearch cluster on Digital Ocean. 

3 hot nodes (8 GB RAM)
1 cold node (2 GB RAM)
1 frozen node (2 GB RAM)

The lastest version of Elastic, 9.1.5, should be used.
## Why

```
# Explain the business value and problem this solves.
This is to create small PoC self-managed Elasticsearch clusters


```

## Success criteria
The deployment supports an "air-gapped mode":

**IMPORTANT NOTE ON "AIR-GAPPED" MODE**:
The current implementation is a **demonstration/learning setup** that shows how to configure Fleet for air-gapped operation:
- Installation Phase: All components (Elasticsearch, Kibana, EPR, Artifact Registry) are installed from the internet during deployment
- Post-Installation: Fleet is configured to use local EPR and Artifact Registry instead of public Elastic services
- This demonstrates the architecture pattern for air-gapped environments without the complexity of pre-downloading packages

For a TRUE air-gapped deployment (no internet access during installation), packages would need to be pre-downloaded and transferred to the droplets. The current setup focuses on demonstrating local registry usage for Fleet.

Elasticsearch Air-Gapped Deployment Guide
Overview
An air-gapped Elasticsearch deployment requires pre-downloading all components and hosting them locally since the environment has no internet access. The main challenge is replacing external dependencies with local alternatives.
What You Need to Deploy
Core Components

Elasticsearch - The search engine itself
Kibana - Web UI for managing Elasticsearch
Elastic Package Registry (EPR) - Provides integrations and packages for Kibana
Elastic Artifact Registry - Hosts binaries for Elastic Agent upgrades and installations

Optional Components (as needed)

Elastic Agent / Fleet Server - For centralized agent management
Beats - Lightweight data shippers (Filebeat, Metricbeat, etc.)
GeoIP databases - For geolocation features
Machine Learning models - For NLP and ML features


Repository Deployment - Best Practices
1. Elastic Package Registry (EPR)
Recommended Approach: Container-based deployment using Docker
Preparation Phase (Internet-Connected Machine)
Step 1: Download the EPR Docker image
bash# Use version-specific image (replace with your Elasticsearch version)
docker pull docker.elastic.co/package-registry/distribution:9.1.5

# Save the image to a tar file
docker save docker.elastic.co/package-registry/distribution:9.1.5 -o epr-9.1.5.tar
Step 2: Transfer the tar file to your air-gapped environment
Deployment Phase (Air-Gapped Environment)
Step 3: Load the Docker image
bash# Load the image
docker load -i epr-9.1.5.tar
Step 4: Run the EPR container (Basic)
bashdocker run -d \
  --name elastic-epr \
  --restart always \
  -p 8443:8443 \
  docker.elastic.co/package-registry/distribution:9.1.5
Step 5: Run the EPR container with TLS (Production)
bashdocker run -d \
  --name elastic-epr \
  --restart always \
  -p 8443:8443 \
  -v /etc/elastic/epr/epr.pem:/etc/ssl/epr.crt:ro \
  -v /etc/elastic/epr/epr-key.pem:/etc/ssl/epr.key:ro \
  -e EPR_ADDRESS=0.0.0.0:8443 \
  -e EPR_TLS_CERT=/etc/ssl/epr.crt \
  -e EPR_TLS_KEY=/etc/ssl/epr.key \
  docker.elastic.co/package-registry/distribution:9.1.5
Step 6: Run with health monitoring (Optional)
bashdocker run -d \
  --name elastic-epr \
  --restart always \
  -p 8443:8443 \
  --health-cmd "curl -f -L http://127.0.0.1:8443/health" \
  --health-interval 30s \
  --health-timeout 10s \
  --health-retries 3 \
  docker.elastic.co/package-registry/distribution:9.1.5
Step 7: Verify EPR is running
bash# Check container status
docker ps

# Check health endpoint
curl http://localhost:8443/health
# Should return 200 OK

# Check logs
docker logs elastic-epr

2. Elastic Artifact Registry
Recommended Approach: NGINX Docker container - Simple and consistent with EPR
Preparation Phase (Internet-Connected Machine)
Step 1: Download artifacts from Elastic's public registry
bash#!/usr/bin/env bash
set -o nounset -o errexit -o pipefail

STACK_VERSION=9.1.5
ARTIFACT_DOWNLOADS_BASE_URL=https://artifacts.elastic.co/downloads
DOWNLOAD_BASE_DIR=/path/to/downloads

# Common packages for Linux x86_64
COMMON_PACKAGE_PREFIXES="apm-server/apm-server \
  beats/auditbeat/auditbeat \
  beats/elastic-agent/elastic-agent \
  beats/filebeat/filebeat \
  beats/heartbeat/heartbeat \
  beats/metricbeat/metricbeat \
  beats/osquerybeat/osquerybeat \
  beats/packetbeat/packetbeat \
  cloudbeat/cloudbeat \
  endpoint-dev/endpoint-security \
  fleet-server/fleet-server"

# Windows-only packages
WIN_ONLY_PACKAGE_PREFIXES="beats/winlogbeat/winlogbeat"

function download_packages() {
  local url_suffix="$1"
  local package_prefixes="$2"
  local _url_suffixes="$url_suffix ${url_suffix}.sha512 ${url_suffix}.asc"
  local _pkg_dir=""
  local _dl_url=""
  
  for _download_prefix in $package_prefixes; do
    for _pkg_url_suffix in $_url_suffixes; do
      _pkg_dir=$(dirname ${DOWNLOAD_BASE_DIR}/${_download_prefix})
      _dl_url="${ARTIFACT_DOWNLOADS_BASE_URL}/${_download_prefix}-${_pkg_url_suffix}"
      mkdir -p $_pkg_dir
      curl -o "${_pkg_dir}/$(basename ${_download_prefix}-${_pkg_url_suffix})" "$_dl_url"
    done
  done
}

# Download for Linux
PKG_URL_SUFFIX="${STACK_VERSION}-linux-x86_64.tar.gz"
download_packages "$PKG_URL_SUFFIX" "$COMMON_PACKAGE_PREFIXES"

# Download for Windows
PKG_URL_SUFFIX="${STACK_VERSION}-windows-x86_64.zip"
download_packages "$PKG_URL_SUFFIX" "$COMMON_PACKAGE_PREFIXES"
download_packages "$PKG_URL_SUFFIX" "$WIN_ONLY_PACKAGE_PREFIXES"

# Download RPM and DEB packages for Elastic Agent
download_packages "${STACK_VERSION}-x86_64.rpm" "beats/elastic-agent/elastic-agent"
download_packages "${STACK_VERSION}-amd64.deb" "beats/elastic-agent/elastic-agent"
Step 2: Download NGINX Docker image
bash# Pull official NGINX image
docker pull nginx:alpine

# Save to tar file
docker save nginx:alpine -o nginx-alpine.tar
Step 3: Transfer artifacts and NGINX image to air-gapped environment
Deployment Phase (Air-Gapped Environment)
Step 4: Load NGINX Docker image
bashdocker load -i nginx-alpine.tar
Step 5: Create directory for artifacts on the host
bash# Create directory for artifacts
sudo mkdir -p /opt/elastic-packages

# Copy downloaded artifacts maintaining directory structure
sudo cp -r /path/to/downloaded/artifacts/* /opt/elastic-packages/

# Set proper permissions
sudo chmod -R 755 /opt/elastic-packages
Step 6: Create NGINX configuration file
Create /opt/elastic-packages/nginx.conf:
nginxuser nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    sendfile on;
    keepalive_timeout 65;
    
    server {
        listen 9080 default_server;
        server_name _;
        root /usr/share/nginx/html;
        
        location / {
            autoindex on;
        }
    }
}
Step 7: Run NGINX Docker container
bashdocker run -d \
  --name elastic-artifacts \
  --restart always \
  -p 9080:9080 \
  -v /opt/elastic-packages:/usr/share/nginx/html:ro \
  -v /opt/elastic-packages/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine
Alternative: Simpler configuration without custom nginx.conf
bash# Use default NGINX config with custom port
docker run -d \
  --name elastic-artifacts \
  --restart always \
  -p 9080:80 \
  -v /opt/elastic-packages:/usr/share/nginx/html:ro \
  nginx:alpine
Step 8: Test the artifact registry
bash# Check container status
docker ps

# Test access to artifacts
curl http://localhost:9080/

# Should show directory listing of artifacts

# Check logs
docker logs elastic-artifacts
Important Note: When setting up your own web server to function as the Elastic Artifact Registry, it is recommended not to use TLS as there are currently no direct ways to establish certificate trust between Elastic Agents and this service Air gapped install | Elastic Docs.

Configure Kibana to Use Local Repositories
Step 1: Edit Kibana configuration (/etc/kibana/kibana.yml):
yaml# Point to your local Elastic Package Registry
xpack.fleet.registryUrl: "http://your-epr-server:8443"

# Enable air-gapped mode in Fleet
xpack.fleet.agentPolicies.airgapped.enabled: true
Step 2: If using TLS with EPR, configure certificate trust
Add to Kibana startup files (e.g., /etc/default/kibana or systemd service):
bashNODE_EXTRA_CA_CERTS="/etc/kibana/certs/ca-cert.pem"
Step 3: Configure Fleet to use local Artifact Registry
In Kibana UI:

Navigate to Fleet → Settings
Update Agent Binary Download settings
Set custom artifact registry URL: http://your-artifact-server:9080

## Implementation Phases

### Phase 1: Air-Gapped Elasticsearch Cluster (Minimal)
**Objective**: Make the 5-node Elasticsearch cluster deployable without internet access

**Tasks**:
1. **Preparation Phase** (Internet-Connected Machine):
   - Create download script to fetch Elasticsearch 9.2.0 DEB package
   - Download Elasticsearch DEB: `elasticsearch-9.2.0-amd64.deb`
   - Download required dependencies:
     - OpenJDK 17 JRE headless DEB
     - `apt-transport-https`, `ca-certificates`, `curl`, `jq` DEBs
   - Download GPG keys for verification (optional)
   - Store all packages in `terraform/packages/` directory

2. **Terraform Infrastructure Updates**:
   - Add file provisioner to upload DEB packages to each droplet
   - Upload packages to `/tmp/elasticsearch-install/` on droplets
   - Ensure proper file permissions

3. **Installation Script Updates** (`install_elasticsearch_secure.sh`):
   - Remove all `apt-get update` calls that require internet
   - Remove Elasticsearch repository addition
   - Install from local DEB packages using `dpkg -i`
   - Handle dependency installation from local packages
   - Keep all existing security features (TLS, RBAC, etc.)

4. **Validation**:
   - Deploy cluster without internet access on droplets
   - Verify all 5 nodes form cluster successfully
   - Verify security features work (TLS, authentication, etc.)
   - Verify searchable snapshots configuration

**Deliverables**:
- `terraform/scripts/download_packages.sh` - Download script for preparation phase
- `terraform/packages/` - Directory structure for packages
- Updated `terraform/main.tf` - File provisioners for package upload
- Updated `terraform/scripts/install_elasticsearch_secure.sh` - Air-gapped installation
- Updated `README.md` - Documentation for air-gapped deployment process

### Phase 2: Full Elastic Stack with Fleet (Optional)
**Objective**: Add Kibana, Fleet Server, EPR, and Artifact Registry for complete air-gapped deployment

**Tasks**:
1. **Additional Infrastructure**:
   - Add Kibana droplet (4GB RAM recommended)
   - Add EPR server droplet with Docker (2GB RAM)
   - Add Artifact Registry server droplet with Docker (2GB RAM)
   - Update VPC and firewall rules for new components

2. **Elastic Package Registry (EPR)**:
   - Download EPR Docker image (9.2.0 version)
   - Create Terraform resources for EPR server
   - Configure EPR to run on port 8443
   - Optional: Add TLS configuration

3. **Elastic Artifact Registry**:
   - Download all Elastic Agent, Fleet Server, and Beats packages
   - Download NGINX Docker image
   - Create Terraform resources for Artifact Registry
   - Configure NGINX to serve artifacts on port 9080
   - Create directory structure for artifacts

4. **Kibana Integration**:
   - Install Kibana from local DEB package
   - Configure Kibana to use local EPR
   - Configure Fleet settings to use local Artifact Registry
   - Set up air-gapped mode in Fleet configuration

5. **Fleet Server** (Optional):
   - Deploy Fleet Server using local packages
   - Configure Fleet policies
   - Test agent enrollment

**Deliverables**:
- Terraform resources for Kibana, EPR, and Artifact Registry droplets
- Docker installation and configuration scripts
- Kibana air-gapped configuration
- Updated firewall rules
- Documentation for Fleet setup

## Success Criteria

```
# Define measurable success metrics and acceptance criteria.

**Phase 1 Success Criteria**:
- Elasticsearch cluster deploys successfully without any internet access on droplets
- All 5 nodes (3 hot, 1 cold, 1 frozen) form a healthy cluster
- TLS certificates are properly configured and validated
- RBAC users (elastic, admin, monitor, ingest) are created with correct permissions
- API keys are generated successfully
- Searchable snapshot repository can be configured with DigitalOcean Spaces
- Audit logging is enabled and functioning
- Firewall rules follow zero-trust/least-privilege principles
- SSH access restricted to non-root esadmin user only

**Phase 2 Success Criteria** (Optional):
- Kibana accessible and connected to Elasticsearch cluster
- EPR running and serving packages to Kibana
- Artifact Registry serving Elastic Agent binaries
- Fleet Server can be configured (if implemented)
- All components operate without internet access


```
## Documentation and references

```
https://www.elastic.co/docs/

https://www.elastic.co/docs/deploy-manage/deploy/self-managed/installing-elasticsearch#installation-methods
https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-kibana



https://registry.terraform.io/providers/elastic/elasticstack/latest

https://registry.terraform.io/providers/digitalocean/digitalocean/latest


```

## Validation loop (Optional)

```
# Describe how to validate the implementation works correctly.
# Example: "1. Run test suite: npm test
#          2. Start local server: npm run dev
#          3. Test with Postman collection: ./tests/postman/"



```

## Syntax and style (Optional)

```
# Specify any coding standards or style preferences beyond the defaults.
# The template already includes Black, isort, and type hints.
# Example: "- Use async/await for all database operations
#          - Prefer composition over inheritance"



```

## Unit tests

```
# Describe the testing approach and any specific test cases needed.
# Example: "- Test all API endpoints with valid and invalid inputs
#          - Mock external services
#          - Test error handling and edge cases"



```

## Integration tests (Optional)

```
# Describe end-to-end testing requirements if applicable.
# Example: "- Test full order workflow from creation to delivery
#          - Test with real database (using test containers)
#          - Verify email notifications are sent"



```

## Security requirements (Optional)

```
# List specific security requirements beyond the template's built-in checks.
# Example: "- Implement rate limiting on all endpoints
#          - Audit log all data modifications
#          - Encrypt PII in database"



```