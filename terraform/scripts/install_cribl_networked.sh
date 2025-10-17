#!/bin/bash
set -e

# NETWORKED Cribl Stream Installation Script
# Installs Cribl Stream from internet repositories

# Variables passed from Terraform
CRIBL_VERSION="${cribl_version}"
CRIBL_LEADER_MODE="${cribl_leader_mode}"
CRIBL_LEADER_URL="${cribl_leader_url}"
CRIBL_AUTH_TOKEN="${cribl_auth_token}"
ELASTICSEARCH_URL="${elasticsearch_url}"
ELASTICSEARCH_PASSWORD="${elasticsearch_password}"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting networked Cribl Stream installation..."

# Get private IP
PRIVATE_IP=${dollar}(hostname -I | awk '{print $$1}')
log "Private IP: $${PRIVATE_IP}"

# Update package lists
log "Updating package lists..."
apt-get update

# Install prerequisites
log "Installing prerequisites..."
apt-get install -y curl gnupg apt-transport-https

# Add Cribl GPG key
log "Adding Cribl GPG key..."
curl -fsSL https://cdn.cribl.io/dl/cribl-gpg-public.key | gpg --dearmor -o /usr/share/keyrings/cribl-archive-keyring.gpg

# Add Cribl repository
log "Adding Cribl repository..."
echo "deb [signed-by=/usr/share/keyrings/cribl-archive-keyring.gpg] https://cdn.cribl.io/apt-repos/ stable main" | tee /etc/apt/sources.list.d/cribl.list

# Update package lists with new repository
log "Updating package lists with Cribl repository..."
apt-get update

# Install Cribl Stream
log "Installing Cribl Stream version $${CRIBL_VERSION}..."
apt-get install -y cribl=$${CRIBL_VERSION}-1

# Verify installation
if [ ! -d "/opt/cribl" ]; then
    log "ERROR: Cribl installation directory not found"
    exit 1
fi
log "Cribl Stream installed successfully"

# Create non-root admin user
log "Creating cribl admin user..."
useradd -m -s /bin/bash cribladmin || true
usermod -aG sudo cribladmin
echo "cribladmin ALL=(ALL) NOPASSWD: /bin/systemctl * cribl" >> /etc/sudoers.d/cribladmin

# Copy SSH keys from root to cribladmin
log "Copying SSH keys to cribladmin user..."
mkdir -p /home/cribladmin/.ssh
cp /root/.ssh/authorized_keys /home/cribladmin/.ssh/authorized_keys
chown -R cribladmin:cribladmin /home/cribladmin/.ssh
chmod 700 /home/cribladmin/.ssh
chmod 600 /home/cribladmin/.ssh/authorized_keys

# Secure SSH
log "Hardening SSH configuration..."
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Configure Cribl based on mode
if [[ "$${CRIBL_LEADER_MODE}" == "worker" ]]; then
  log "Configuring Cribl in Worker mode..."

  if [[ -z "$${CRIBL_LEADER_URL}" ]] || [[ -z "$${CRIBL_AUTH_TOKEN}" ]]; then
    log "ERROR: Worker mode requires CRIBL_LEADER_URL and CRIBL_AUTH_TOKEN"
    exit 1
  fi

  # Configure worker mode
  cat > /opt/cribl/local/cribl/auth/cribl.secret << EOF
$${CRIBL_AUTH_TOKEN}
EOF

  # Set leader URL
  /opt/cribl/bin/cribl mode-worker -H "$${CRIBL_LEADER_URL}" -u admin -p "$${CRIBL_AUTH_TOKEN}"

  log "Worker mode configured with leader: $${CRIBL_LEADER_URL}"
else
  log "Configuring Cribl in Standalone mode..."

  # Standalone mode - set admin password
  ADMIN_PASSWORD=$(openssl rand -base64 16)
  /opt/cribl/bin/cribl set-password -u admin -p "$${ADMIN_PASSWORD}"

  # Save credentials
  cat > /home/cribladmin/cribl_credentials.txt << EOF
Cribl Stream Credentials
========================
URL: http://$${PRIVATE_IP}:9000
Username: admin
Password: $${ADMIN_PASSWORD}

Elasticsearch Configuration
===========================
URL: $${ELASTICSEARCH_URL}
Username: ingest
Password: <use ingest_password from Terraform output>
EOF
  chmod 600 /home/cribladmin/cribl_credentials.txt
  chown cribladmin:cribladmin /home/cribladmin/cribl_credentials.txt

  log "Standalone mode configured"
  log "Admin password saved to /home/cribladmin/cribl_credentials.txt"
fi

# Create Elasticsearch destination configuration script
cat > /home/cribladmin/configure_elasticsearch_destination.sh << 'SCRIPT'
#!/bin/bash
# Configure Elasticsearch destination in Cribl
# This script creates an Elasticsearch destination via Cribl API

set -e

CRIBL_URL="http://localhost:9000"
CRIBL_USER="admin"
CRIBL_PASS="$1"
ES_URL="__ES_URL__"
ES_USER="ingest"
ES_PASS="__ES_PASS__"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <cribl_admin_password>"
  exit 1
fi

echo "Configuring Elasticsearch destination..."

# Wait for Cribl to be ready
sleep 30

# Create Elasticsearch destination
curl -X POST "$CRIBL_URL/api/v1/system/destinations" \
  -u "$CRIBL_USER:$CRIBL_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "elasticsearch-main",
    "type": "elasticsearch",
    "systemFields": ["cribl_pipe"],
    "streamtags": [],
    "sendToRoutes": true,
    "disabledRoutes": [],
    "enabled": true,
    "bulkAPI": {
      "url": "'$ES_URL'/_bulk",
      "authType": "basic",
      "username": "'$ES_USER'",
      "password": "'$ES_PASS'",
      "rejectUnauthorized": false,
      "enableAckSending": false,
      "maxPayloadSizeKB": 4096,
      "maxPayloadEvents": 500,
      "flushPeriodSec": 1,
      "compressionLevel": 0
    }
  }'

echo ""
echo "Elasticsearch destination configured successfully!"
echo "Access Cribl UI to create routes and pipelines"
SCRIPT

# Replace placeholders
sed -i "s|__ES_URL__|$${ELASTICSEARCH_URL}|g" /home/cribladmin/configure_elasticsearch_destination.sh
sed -i "s|__ES_PASS__|$${ELASTICSEARCH_PASSWORD}|g" /home/cribladmin/configure_elasticsearch_destination.sh

chmod +x /home/cribladmin/configure_elasticsearch_destination.sh
chown cribladmin:cribladmin /home/cribladmin/configure_elasticsearch_destination.sh

# Set Cribl to bind to private IP
log "Configuring Cribl to bind to $${PRIVATE_IP}..."
mkdir -p /opt/cribl/local/cribl/
cat > /opt/cribl/local/cribl/cribl.yml << EOF
api:
  host: $${PRIVATE_IP}
  port: 9000
EOF

# Enable and start Cribl
log "Starting Cribl Stream service..."
systemctl enable cribl
systemctl start cribl

# Wait for Cribl to start
log "Waiting for Cribl to start..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%%{http_code}" http://localhost:9000/login | grep -q "200"; then
    log "Cribl Stream is responding"
    break
  fi
  sleep 5
done

log "========================================="
log "Networked Cribl Stream installation complete!"
log "========================================="
log "Mode: $${CRIBL_LEADER_MODE}"
log "IP: $${PRIVATE_IP}"
log "UI: http://$${PRIVATE_IP}:9000"
if [[ "$${CRIBL_LEADER_MODE}" == "standalone" ]]; then
  log "Credentials: /home/cribladmin/cribl_credentials.txt"
  log "Configure ES destination: ./configure_elasticsearch_destination.sh <admin_password>"
fi
log "SSH access restricted to cribladmin user"
log "========================================="
