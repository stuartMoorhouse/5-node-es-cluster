#!/bin/bash
set -e

# EPR (Elastic Package Registry) Installation Script
# Installs Docker from internet and runs EPR container
# Despite the "airgapped" name, this installs from the internet during setup
# "Airgapped" refers to the Fleet configuration that will use this local EPR

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting EPR installation from internet..."

# Wait for cloud-init to finish to avoid apt lock conflicts
log "Waiting for cloud-init to complete..."
cloud-init status --wait

# Get private IP
PRIVATE_IP=${dollar}(hostname -I | awk '{print $$1}')
log "Private IP: $${PRIVATE_IP}"

# Update package lists
log "Updating package lists..."
apt-get update

# Install prerequisites
log "Installing prerequisites..."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker GPG key
log "Adding Docker GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
log "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package lists with Docker repository
log "Updating package lists with Docker repository..."
apt-get update

# Install Docker
log "Installing Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io

# Start Docker service
log "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Verify Docker is running
if ! docker --version; then
    log "ERROR: Docker installation failed"
    exit 1
fi
log "Docker installed successfully: $(docker --version)"

# Pull EPR Docker image from internet
log "Pulling EPR Docker image from Docker Hub..."
# EPR version 9.1.5 corresponds to Elasticsearch 9.1.5
EPR_VERSION="v9.1.5"
EPR_IMAGE="docker.elastic.co/package-registry/distribution:$${EPR_VERSION}"

docker pull "$${EPR_IMAGE}"
log "EPR Docker image pulled successfully"

# Create non-root admin user
log "Creating esadmin user..."
useradd -m -s /bin/bash esadmin || true
usermod -aG sudo,docker esadmin
echo "esadmin ALL=(ALL) NOPASSWD: /usr/bin/docker" >> /etc/sudoers.d/esadmin

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
for i in {1..60}; do
  CONTAINER_STATUS=$(docker inspect --format='{{.State.Health.Status}}' elastic-epr 2>/dev/null || echo "starting")
  log "EPR container health status: $${CONTAINER_STATUS} (attempt $i/60)"

  if [ "$${CONTAINER_STATUS}" = "healthy" ]; then
    log "EPR is healthy"
    break
  fi
  sleep 5
done

# Verify EPR is responding
log "Verifying EPR health endpoint..."
if curl -s http://localhost:8443/health | grep -q "ok\|OK"; then
    log "EPR health check passed"
else
    log "WARN: EPR health check failed, checking container logs..."
    docker logs elastic-epr | tail -20
fi

# Create management script
cat > /home/esadmin/manage_epr.sh << 'SCRIPT'
#!/bin/bash
# EPR Management Script

case "$1" in
  status)
    echo "=== Docker Container Status ==="
    docker ps -f name=elastic-epr
    echo ""
    echo "=== EPR Health Check ==="
    curl -s http://localhost:8443/health | jq . 2>/dev/null || curl -s http://localhost:8443/health
    ;;
  logs)
    docker logs elastic-epr "$${@:2}"
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
  search)
    if [ -z "$2" ]; then
      echo "Usage: $0 search <package-name>"
      exit 1
    fi
    echo "Searching for package: $2"
    curl -s "http://localhost:8443/search?package=$2" | jq .
    ;;
  *)
    echo "Usage: $0 {status|logs|restart|stop|start|search <package>}"
    echo ""
    echo "Examples:"
    echo "  $0 status        - Show container and health status"
    echo "  $0 logs          - Show container logs"
    echo "  $0 logs -f       - Follow container logs"
    echo "  $0 search apache - Search for Apache integration"
    exit 1
    ;;
esac
SCRIPT

chmod +x /home/esadmin/manage_epr.sh
chown esadmin:esadmin /home/esadmin/manage_epr.sh

log "========================================="
log "EPR installation complete!"
log "========================================="
log "EPR URL (internal): http://$${PRIVATE_IP}:8443"
log "Health endpoint: http://$${PRIVATE_IP}:8443/health"
log "Docker container: elastic-epr"
log "Docker image: $${EPR_IMAGE}"
log ""
log "Management:"
log "  SSH: ssh esadmin@<ip>"
log "  Script: /home/esadmin/manage_epr.sh status"
log ""
log "Installation method:"
log "  ✓ Docker and EPR installed from internet"
log "  ✓ EPR running locally on port 8443"
log "  → Configure Fleet to use this local EPR for airgapped operation"
log "========================================="
