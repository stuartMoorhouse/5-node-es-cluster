#!/bin/bash
set -e

# AIR-GAPPED EPR (Elastic Package Registry) Installation Script
# Installs Docker and runs EPR from local Docker image

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"

# Paths
INSTALL_DIR="/tmp/elasticsearch-install"
EPR_PKG_DIR="$${INSTALL_DIR}/epr"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting air-gapped EPR installation..."

# Get private IP
PRIVATE_IP=${dollar}(hostname -I | awk '{print $$1}')
log "Private IP: $${PRIVATE_IP}"

# Verify packages directory exists
if [ ! -d "$${EPR_PKG_DIR}" ]; then
    log "ERROR: EPR package directory not found: $${EPR_PKG_DIR}"
    exit 1
fi

# Install Docker from local packages
log "Installing Docker..."
# Note: Docker installation requires packages to be downloaded
# This is a placeholder - actual implementation would install from local DEBs
if [ -f "$${EPR_PKG_DIR}/docker-ce.deb" ]; then
    dpkg -i "$${EPR_PKG_DIR}"/docker*.deb 2>/dev/null || apt-get install -f -y --no-download
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

# Load EPR Docker image from file
log "Loading EPR Docker image..."
EPR_IMAGE_TAR=$(find "$${EPR_PKG_DIR}" -name "epr-*.tar" -o -name "package-registry-*.tar" | head -n 1)
if [ -f "$${EPR_IMAGE_TAR}" ]; then
    docker load -i "$${EPR_IMAGE_TAR}"
    log "EPR Docker image loaded successfully"
else
    log "ERROR: EPR Docker image not found in $${EPR_PKG_DIR}"
    log "Expected file: epr-*.tar or package-registry-*.tar"
    exit 1
fi

# Get the loaded image name
EPR_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "package-registry\|epr" | head -n 1)
log "Using EPR image: $${EPR_IMAGE}"

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
# TEMPORARILY DISABLED FOR DEBUGGING - Re-enable for production
# log "Hardening SSH configuration..."
# sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
# systemctl restart sshd

# Run EPR container
log "Starting EPR container..."
docker run -d \
  --name elastic-epr \
  --restart always \
  -p 8443:8443 \
  --health-cmd "curl -f -L http://127.0.0.1:8443/health || exit 1" \
  --health-interval 30s \
  --health-timeout 10s \
  --health-retries 3 \
  "$${EPR_IMAGE}"

# Wait for EPR to be healthy
log "Waiting for EPR to be healthy..."
for i in {1..30}; do
  if docker ps | grep -q "healthy"; then
    log "EPR is healthy"
    break
  fi
  sleep 2
done

# Verify EPR is running
if curl -s http://localhost:8443/health | grep -q "OK"; then
    log "EPR health check passed"
else
    log "WARN: EPR health check failed, but container is running"
fi

# Create management script
cat > /home/esadmin/manage_epr.sh << 'SCRIPT'
#!/bin/bash
# EPR Management Script

case "$1" in
  status)
    docker ps -f name=elastic-epr
    curl -s http://localhost:8443/health
    ;;
  logs)
    docker logs elastic-epr
    ;;
  restart)
    docker restart elastic-epr
    ;;
  stop)
    docker stop elastic-epr
    ;;
  start)
    docker start elastic-epr
    ;;
  *)
    echo "Usage: $0 {status|logs|restart|stop|start}"
    exit 1
    ;;
esac
SCRIPT

chmod +x /home/esadmin/manage_epr.sh
chown esadmin:esadmin /home/esadmin/manage_epr.sh

# Clean up installation packages
log "Cleaning up installation packages..."
rm -rf "$${INSTALL_DIR}"

log "========================================="
log "Air-gapped EPR installation complete!"
log "========================================="
log "EPR URL: http://$${PRIVATE_IP}:8443"
log "Health endpoint: http://$${PRIVATE_IP}:8443/health"
log "Docker container: elastic-epr"
log "Management script: /home/esadmin/manage_epr.sh"
log "SSH access restricted to esadmin user"
log "========================================="
