#!/bin/bash
set -e

# AIR-GAPPED Artifact Registry Installation Script
# Installs Docker and runs NGINX to serve Elastic Agent artifacts

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"

# Paths
INSTALL_DIR="/tmp/elasticsearch-install"
NGINX_PKG_DIR="$${INSTALL_DIR}/nginx"
ARTIFACTS_DIR="$${INSTALL_DIR}/artifacts"
HOST_ARTIFACTS_DIR="/opt/elastic-artifacts"

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
    log "ERROR: NGINX package directory not found: $${NGINX_PKG_DIR}"
    exit 1
fi

# Install Docker
log "Installing Docker..."
if [ -f "$${NGINX_PKG_DIR}/docker-ce.deb" ]; then
    dpkg -i "$${NGINX_PKG_DIR}"/docker*.deb 2>/dev/null || apt-get install -f -y --no-download
    log "Docker installed from local packages"
else
    log "WARN: Docker packages not found, attempting online install"
    apt-get update
    apt-get install -y docker.io
fi

# Start Docker service
log "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Load NGINX Docker image from file
log "Loading NGINX Docker image..."
NGINX_IMAGE_TAR=$(find "$${NGINX_PKG_DIR}" -name "nginx*.tar" | head -n 1)
if [ -f "$${NGINX_IMAGE_TAR}" ]; then
    docker load -i "$${NGINX_IMAGE_TAR}"
    log "NGINX Docker image loaded successfully"
else
    log "ERROR: NGINX Docker image not found in $${NGINX_PKG_DIR}"
    log "Expected file: nginx*.tar"
    exit 1
fi

# Get the loaded image name
NGINX_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep nginx | head -n 1)
log "Using NGINX image: $${NGINX_IMAGE}"

# Create artifacts directory on host
log "Setting up artifacts directory..."
mkdir -p "$${HOST_ARTIFACTS_DIR}"

# Copy artifacts if they exist
if [ -d "$${ARTIFACTS_DIR}" ]; then
    log "Copying artifacts to $${HOST_ARTIFACTS_DIR}..."
    cp -r "$${ARTIFACTS_DIR}"/* "$${HOST_ARTIFACTS_DIR}/" || true
    log "Artifacts copied"
else
    log "WARN: No artifacts found in $${ARTIFACTS_DIR}"
    log "Creating placeholder structure"
    mkdir -p "$${HOST_ARTIFACTS_DIR}"/{beats,fleet-server,elastic-agent}
fi

# Set proper permissions
chmod -R 755 "$${HOST_ARTIFACTS_DIR}"

# Create NGINX configuration
log "Creating NGINX configuration..."
mkdir -p /etc/nginx-artifacts
cat > /etc/nginx-artifacts/nginx.conf << 'EOF'
user nginx;
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
            autoindex_exact_size off;
            autoindex_localtime on;
        }
    }
}
EOF

# Create non-root admin user
log "Creating esadmin user..."
useradd -m -s /bin/bash esadmin || true
usermod -aG sudo,docker esadmin

# Copy SSH keys from root to esadmin
log "Copying SSH keys to esadmin user..."
mkdir -p /home/esadmin/.ssh
cp /root/.ssh/authorized_keys /home/esadmin/.ssh/authorized_keys
chown -R esadmin:esadmin /home/esadmin/.ssh
chmod 700 /home/esadmin/.ssh
chmod 600 /home/esadmin/.ssh/authorized_keys

# Secure SSH
log "Hardening SSH configuration..."
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Run NGINX container
log "Starting NGINX container..."
docker run -d \
  --name elastic-artifacts \
  --restart always \
  -p 9080:9080 \
  -v "$${HOST_ARTIFACTS_DIR}:/usr/share/nginx/html:ro" \
  -v /etc/nginx-artifacts/nginx.conf:/etc/nginx/nginx.conf:ro \
  "$${NGINX_IMAGE}"

# Wait for NGINX to start
log "Waiting for NGINX to start..."
sleep 5

# Verify NGINX is running
if curl -s http://localhost:9080/ | grep -q "Index of\|nginx"; then
    log "NGINX is serving artifacts successfully"
else
    log "WARN: NGINX health check uncertain, but container is running"
fi

# Create management script
cat > /home/esadmin/manage_artifacts.sh << 'SCRIPT'
#!/bin/bash
# Artifact Registry Management Script

case "$1" in
  status)
    docker ps -f name=elastic-artifacts
    curl -s http://localhost:9080/
    ;;
  logs)
    docker logs elastic-artifacts
    ;;
  restart)
    docker restart elastic-artifacts
    ;;
  stop)
    docker stop elastic-artifacts
    ;;
  start)
    docker start elastic-artifacts
    ;;
  list)
    echo "Available artifacts:"
    find /opt/elastic-artifacts -type f -name "*.tar.gz" -o -name "*.zip" -o -name "*.deb" -o -name "*.rpm"
    ;;
  *)
    echo "Usage: $0 {status|logs|restart|stop|start|list}"
    exit 1
    ;;
esac
SCRIPT

chmod +x /home/esadmin/manage_artifacts.sh
chown esadmin:esadmin /home/esadmin/manage_artifacts.sh

# Create artifact upload instructions
cat > /home/esadmin/README_ARTIFACTS.md << 'EOF'
# Artifact Registry Usage

This server hosts Elastic Agent, Fleet Server, and Beats packages for air-gapped deployments.

## Adding New Artifacts

To add artifacts to the registry:

```bash
# Copy artifacts to the host directory
sudo cp /path/to/artifact.tar.gz /opt/elastic-artifacts/

# Verify permissions
sudo chmod 644 /opt/elastic-artifacts/artifact.tar.gz

# Artifacts are immediately available
curl http://localhost:9080/
```

## Directory Structure

Recommended structure:
```
/opt/elastic-artifacts/
├── beats/
│   ├── elastic-agent/
│   ├── filebeat/
│   └── metricbeat/
├── fleet-server/
└── endpoint-dev/
```

## Verifying Artifacts

```bash
# List all artifacts
./manage_artifacts.sh list

# Check web interface
curl http://localhost:9080/
```
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
log "Docker container: elastic-artifacts"
log "Management script: /home/esadmin/manage_artifacts.sh"
log "Documentation: /home/esadmin/README_ARTIFACTS.md"
log "SSH access restricted to esadmin user"
log "========================================="
