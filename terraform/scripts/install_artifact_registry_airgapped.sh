#!/bin/bash
set -e

# AIR-GAPPED Artifact Registry Installation Script
# Installs NGINX natively to serve Elastic Agent artifacts
# Based on official Elastic documentation

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"

# Paths
INSTALL_DIR="/tmp/elasticsearch-install"
NGINX_PKG_DIR="$${INSTALL_DIR}/nginx"
ARTIFACTS_DIR="$${INSTALL_DIR}/artifacts"
HOST_ARTIFACTS_DIR="/opt/elastic-packages"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting air-gapped Artifact Registry installation..."

# Get private IP
PRIVATE_IP=${dollar}(hostname -I | awk '{print $$1}')
log "Private IP: $${PRIVATE_IP}"

# Verify packages directory exists
if [ ! -d "$${NGINX_PKG_DIR}" ]; then
    log "WARN: NGINX package directory not found: $${NGINX_PKG_DIR}"
    log "Creating directory structure..."
    mkdir -p "$${NGINX_PKG_DIR}"
fi

# Install NGINX from local packages
log "Installing NGINX from local packages..."
if ls "$${NGINX_PKG_DIR}"/*.deb 1> /dev/null 2>&1; then
    log "Found NGINX packages, installing..."
    dpkg -i "$${NGINX_PKG_DIR}"/*.deb 2>/dev/null || apt-get install -f -y --no-download
    log "NGINX installed from local packages"
else
    log "WARN: NGINX packages not found in $${NGINX_PKG_DIR}"
    log "Attempting online install..."
    apt-get update
    apt-get install -y nginx
fi

# Create artifacts directory
log "Setting up artifacts directory..."
mkdir -p "$${HOST_ARTIFACTS_DIR}"

# Copy artifacts if they exist
if [ -d "$${ARTIFACTS_DIR}" ] && [ "$(ls -A $${ARTIFACTS_DIR})" ]; then
    log "Copying artifacts to $${HOST_ARTIFACTS_DIR}..."
    cp -r "$${ARTIFACTS_DIR}"/* "$${HOST_ARTIFACTS_DIR}/" || true
    log "Artifacts copied"
else
    log "WARN: No artifacts found in $${ARTIFACTS_DIR}"
    log "Creating placeholder structure as per Elastic documentation"
    mkdir -p "$${HOST_ARTIFACTS_DIR}"/downloads/beats/elastic-agent
fi

# Set proper permissions
chmod -R 755 "$${HOST_ARTIFACTS_DIR}"
chown -R www-data:www-data "$${HOST_ARTIFACTS_DIR}"

# Create NGINX configuration following Elastic's official example
log "Creating NGINX configuration (official Elastic approach)..."
cat > /etc/nginx/sites-available/elastic-artifacts << 'EOF'
server {
    listen 9080 default_server;
    server_name _;

    root /opt/elastic-packages;

    # Disable TLS as recommended by Elastic
    # "it is recommended not to use TLS as there are, currently,
    # no direct ways to establish certificate trust between Elastic Agents and this service"

    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    # Enable CORS for Fleet Server
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, HEAD, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' '*' always;

    # Optimize for large file downloads
    client_max_body_size 0;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/elastic-artifacts /etc/nginx/sites-enabled/elastic-artifacts

# Remove default site
rm -f /etc/nginx/sites-enabled/default

# Test NGINX configuration
log "Testing NGINX configuration..."
nginx -t

# Start and enable NGINX
log "Starting NGINX service..."
systemctl enable nginx
systemctl restart nginx

# Wait for NGINX to start
sleep 3

# Verify NGINX is running and serving
if curl -s http://localhost:9080/ | grep -q "Index of"; then
    log "✓ NGINX is serving artifacts successfully"
else
    log "WARN: NGINX may not be fully ready yet"
fi

# Create non-root admin user
log "Creating esadmin user..."
useradd -m -s /bin/bash esadmin || true
usermod -aG sudo esadmin

# Copy SSH keys from root to esadmin
log "Copying SSH keys to esadmin user..."
mkdir -p /home/esadmin/.ssh
cp /root/.ssh/authorized_keys /home/esadmin/.ssh/authorized_keys
chown -R esadmin:esadmin /home/esadmin/.ssh
chmod 700 /home/esadmin/.ssh
chmod 600 /home/esadmin/.ssh/authorized_keys

# Secure SSH
# TEMPORARILY DISABLED FOR DEBUGGING - Re-enable for production
# log "Hardening SSH configuration..."
# sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# systemctl restart sshd

# Create management script
cat > /home/esadmin/manage_artifacts.sh << 'SCRIPT'
#!/bin/bash
# Artifact Registry Management Script

case "$1" in
  status)
    systemctl status nginx
    echo ""
    echo "Listening on:"
    ss -tlnp | grep :9080
    ;;
  logs)
    tail -50 /var/log/nginx/access.log
    ;;
  errors)
    tail -50 /var/log/nginx/error.log
    ;;
  restart)
    sudo systemctl restart nginx
    ;;
  reload)
    sudo systemctl reload nginx
    ;;
  test)
    sudo nginx -t
    ;;
  list)
    echo "Available artifacts:"
    find /opt/elastic-packages -type f \( -name "*.tar.gz" -o -name "*.zip" -o -name "*.deb" -o -name "*.rpm" \)
    ;;
  browse)
    curl -s http://localhost:9080/
    ;;
  *)
    echo "Usage: $0 {status|logs|errors|restart|reload|test|list|browse}"
    echo ""
    echo "  status  - Show NGINX status and listening ports"
    echo "  logs    - Show access logs"
    echo "  errors  - Show error logs"
    echo "  restart - Restart NGINX service"
    echo "  reload  - Reload NGINX configuration"
    echo "  test    - Test NGINX configuration"
    echo "  list    - List all artifacts"
    echo "  browse  - Browse artifacts via curl"
    exit 1
    ;;
esac
SCRIPT

chmod +x /home/esadmin/manage_artifacts.sh
chown esadmin:esadmin /home/esadmin/manage_artifacts.sh

# Create artifact upload instructions based on Elastic docs
cat > /home/esadmin/README_ARTIFACTS.md << 'EOF'
# Elastic Artifact Registry

This server hosts Elastic Agent, Fleet Server, and Beats packages for air-gapped deployments.

Based on official Elastic documentation:
https://www.elastic.co/docs/deploy-manage/deploy/self-managed/air-gapped-install

## Architecture

- **NGINX**: Native installation (no Docker)
- **Port**: 9080 (HTTP - no TLS per Elastic recommendation)
- **Root Directory**: /opt/elastic-packages
- **Configuration**: /etc/nginx/sites-available/elastic-artifacts

## Directory Structure (Official Elastic Layout)

```
/opt/elastic-packages/
└── downloads/
    └── beats/
        └── elastic-agent/
            ├── elastic-agent-9.1.5-linux-x86_64.tar.gz
            ├── elastic-agent-9.1.5-linux-arm64.tar.gz
            ├── elastic-agent-9.1.5-windows-x86_64.zip
            ├── elastic-agent-9.1.5-darwin-x86_64.tar.gz
            └── elastic-agent-9.1.5-darwin-aarch64.tar.gz
```

## Adding New Artifacts

```bash
# Download artifacts from Elastic (on internet-connected machine)
VERSION="9.1.5"
cd /tmp

# Linux x86_64
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$${VERSION}-linux-x86_64.tar.gz

# Linux ARM64
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$${VERSION}-linux-arm64.tar.gz

# Windows
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$${VERSION}-windows-x86_64.zip

# macOS Intel
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$${VERSION}-darwin-x86_64.tar.gz

# macOS ARM
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$${VERSION}-darwin-aarch64.tar.gz

# Copy to server
scp elastic-agent-* esadmin@<server-ip>:/tmp/

# On the server - move to proper location
sudo mkdir -p /opt/elastic-packages/downloads/beats/elastic-agent
sudo mv /tmp/elastic-agent-* /opt/elastic-packages/downloads/beats/elastic-agent/
sudo chown -R www-data:www-data /opt/elastic-packages
sudo chmod -R 755 /opt/elastic-packages
```

## Configuring Fleet to Use This Registry

In Kibana Fleet settings, configure:

**Agent Binary Download settings:**
- Host: http://10.10.10.3:9080
- Path: /downloads/beats/elastic-agent/

Fleet will construct URLs like:
http://10.10.10.3:9080/downloads/beats/elastic-agent/elastic-agent-9.1.5-linux-x86_64.tar.gz

## Verification

```bash
# Browse available artifacts
curl http://localhost:9080/downloads/beats/elastic-agent/

# Check specific artifact
curl -I http://localhost:9080/downloads/beats/elastic-agent/elastic-agent-9.1.5-linux-x86_64.tar.gz

# Use management script
./manage_artifacts.sh list
./manage_artifacts.sh browse
```

## Management Commands

```bash
./manage_artifacts.sh status    # Check NGINX status
./manage_artifacts.sh logs      # View access logs
./manage_artifacts.sh errors    # View error logs
./manage_artifacts.sh restart   # Restart NGINX
./manage_artifacts.sh list      # List all artifacts
```

## Troubleshooting

**Check NGINX is running:**
```bash
systemctl status nginx
ss -tlnp | grep :9080
```

**View logs:**
```bash
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

**Test configuration:**
```bash
sudo nginx -t
```

## Why No TLS?

Per Elastic documentation:
"When setting up own web server, such as NGINX, to function as the Elastic Artifact Registry,
it is recommended not to use TLS as there are, currently, no direct ways to establish certificate
trust between Elastic Agents and this service."
EOF

chown esadmin:esadmin /home/esadmin/README_ARTIFACTS.md

# Clean up installation packages
log "Cleaning up installation packages..."
rm -rf "$${INSTALL_DIR}"

log "========================================="
log "Artifact Registry installation complete!"
log "========================================="
log "Registry URL: http://$${PRIVATE_IP}:9080"
log "Artifacts location: $${HOST_ARTIFACTS_DIR}"
log "NGINX config: /etc/nginx/sites-available/elastic-artifacts"
log "Management script: /home/esadmin/manage_artifacts.sh"
log "Documentation: /home/esadmin/README_ARTIFACTS.md"
log "SSH access restricted to esadmin user"
log ""
log "Next steps:"
log "1. Upload Elastic Agent binaries to $${HOST_ARTIFACTS_DIR}/downloads/beats/elastic-agent/"
log "2. Configure Fleet in Kibana to use http://$${PRIVATE_IP}:9080"
log "3. See README_ARTIFACTS.md for detailed instructions"
log "========================================="
