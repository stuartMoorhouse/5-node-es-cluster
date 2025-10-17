# Elasticsearch Cluster Terraform Project

This document provides context and guidelines for Claude when working on this Terraform project.

## Project Overview

This is a Terraform configuration for deploying an Elasticsearch cluster on DigitalOcean with two deployment modes that demonstrate different Fleet/integration architectures.

## Project Structure

- `terraform/` - Terraform configuration files
  - `main.tf` - Core Elasticsearch cluster resources
  - `phase2.tf` - Kibana, EPR, and Artifact Registry
  - `data-sources.tf` - Optional data source VMs (Cribl Stream)
  - `firewall.tf` - Security rules
  - `variables.tf` - Input variables
  - `outputs.tf` - Output values
  - `scripts/` - Installation scripts for each component
  - `packages/` - Package directory (mostly empty, for reference)
- `state/` - Terraform state files (gitignored)
- `README.md` - User-facing documentation
- `CLAUDE.md` - This file (Claude context)

## Deployment Modes

### 1. Networked Mode (Default)
- **Purpose**: Standard deployment with public Elastic infrastructure
- **Fleet Configuration**: Uses public services
  - Package Registry: `epr.elastic.co`
  - Agent Downloads: `artifacts.elastic.co`
- **Installation**: All packages installed from internet during deployment

### 2. Local Package Registry Mode (`deployment_mode = "airgapped"`)
- **Purpose**: Demonstrates air-gapped/isolated architecture patterns
- **Fleet Configuration**: Uses local infrastructure
  - **Local EPR** (Elastic Package Registry): Runs on port 8443
  - **Local Artifact Registry**: Nginx server on port 9080
  - Fleet automatically configured via API to use these local registries
- **Installation**: Same as networked - uses internet during installation
- **Key Difference**: Fleet configuration only - demonstrates how to run isolated from public Elastic services

## Important Architecture Notes

### The "Local Package Registry" Approach

**What It Is:**
- A demonstration/learning setup that shows how to configure Fleet for air-gapped environments
- Installation uses internet connectivity (downloads Elasticsearch, Kibana, etc. from public repos)
- After installation, Fleet is configured to use local registries instead of public Elastic services

**What It Is NOT:**
- A true air-gapped deployment where droplets have NO internet access
- A setup that installs from pre-downloaded .deb packages

**Why This Approach:**
- Simpler and more reliable than true air-gapped installation
- Demonstrates the key architectural difference: using local EPR and Artifact Registry
- Installation process is identical for both modes
- Only Fleet configuration differs between modes

### Installation Scripts

**Both modes use the same installation scripts:**
- `install_elasticsearch_networked.sh` / `install_elasticsearch_airgapped.sh`
- `install_kibana_networked.sh` / `install_kibana_airgapped.sh`
- etc.

**The "airgapped" scripts:**
- Install packages from internet (same as networked)
- Additionally deploy and configure local registries (EPR, Artifact Registry)
- Automatically configure Fleet via API to use local registries

## Key Components

### Elastic Package Registry (EPR)
- **Technology**: Go application running in Docker container
- **Port**: 8443 (HTTP)
- **Purpose**: Serves integration packages (Apache, AWS, Kubernetes, etc.)
- **Docker Image**: `docker.elastic.co/package-registry/distribution:v9.1.5`
- **Replaces**: `epr.elastic.co` in air-gapped mode

### Artifact Registry
- **Technology**: Native Nginx installation (NOT Docker)
- **Port**: 9080 (HTTP, no TLS per Elastic recommendation)
- **Purpose**: Serves Elastic Agent binaries for different platforms
- **Root Directory**: `/opt/elastic-packages/`
- **Configuration**: `/etc/nginx/sites-available/elastic-artifacts`
- **Replaces**: `artifacts.elastic.co` in air-gapped mode

### Fleet Configuration (Air-Gapped Mode Only)

After Kibana starts, the install script automatically:
1. Waits for Kibana API to be ready
2. Initializes Fleet via `POST /api/fleet/setup`
3. Configures Fleet via `PUT /api/fleet/settings`:
   ```json
   {
     "package_registry_url": "http://10.10.10.2:8443",
     "agent_binary_download": {
       "source_uri": "http://10.10.10.3:9080/downloads/"
     }
   }
   ```

This is the "flip the switch" moment - Fleet now uses local infrastructure.

## Development Guidelines

### When Making Changes

1. **Both modes should work identically during installation**
   - Don't create separate installation logic
   - Both modes install from internet

2. **Air-gapped mode adds configuration**
   - Deploy local registries (EPR, Artifact Registry)
   - Configure Fleet to use them

3. **No package upload complexity**
   - We don't upload .deb files to droplets
   - We don't use local package installation
   - Installation always uses `apt` or `curl` from internet

### Firewall Rules

- Both modes allow HTTP/HTTPS outbound during installation
- SSH is always accessible (for demo purposes)
- Consider: Optional iptables rules to block Elastic's public servers after configuration (to prove independence)

### Common Patterns

**Adding a new component:**
1. Create networked install script (installs from internet)
2. If needed for air-gapped demo, create airgapped variant that also sets up local registries
3. Update phase2.tf or appropriate .tf file with conditional logic

**Testing changes:**
```bash
# Test networked mode
terraform apply -var="deployment_mode=networked"

# Test local registry mode
terraform apply -var="deployment_mode=airgapped"
```

## Important Notes

- The variable name is still `deployment_mode = "airgapped"` for backwards compatibility
- In documentation, we call it "Local Package Registry Mode"
- Both modes require internet connectivity during deployment
- The key difference is Fleet configuration, not installation method
- This is a demonstration/learning setup, not production-ready air-gapped deployment

## Troubleshooting

### Kibana not accessible
- Check cloud-init logs: `/var/log/cloud-init-output.log`
- Check Kibana service: `systemctl status kibana`
- Check Kibana logs: `/var/log/kibana/kibana.log`

### Fleet configuration failed
- Manual configuration script available: `/home/esadmin/configure_fleet_airgapped.sh`
- Check Kibana API is responding: `curl http://localhost:5601/api/status`

### EPR or Artifact Registry not working
- EPR: Check Docker container: `docker ps | grep package-registry`
- Artifact Registry: Check nginx: `systemctl status nginx`
- Check ports: `ss -tlnp | grep -E '8443|9080'`
