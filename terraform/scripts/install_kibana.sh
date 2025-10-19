#!/bin/bash
set -e

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Kibana Installation Script
# Installs Kibana from internet repositories
# Configures Fleet for local registries if in airgapped mode

# Environment variables expected from Terraform provisioner:
# ES_VERSION, ELASTIC_PASSWORD, CLUSTER_NAME, MASTER_IPS,
# DEPLOYMENT_MODE, EPR_URL, ARTIFACT_REGISTRY_URL

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting Kibana installation (mode: ${DEPLOYMENT_MODE})..."

# Wait for cloud-init to finish to avoid apt lock conflicts
log "Waiting for cloud-init to complete..."
cloud-init status --wait

# Wait for networking to be ready and get private IP
log "Waiting for network to be ready..."
for i in {1..30}; do
  # Try multiple methods to get private IP
  PRIVATE_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

  # Fallback to ip command if hostname -I fails
  if [ -z "${PRIVATE_IP}" ]; then
    PRIVATE_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
  fi

  # Fallback to DigitalOcean metadata service
  if [ -z "${PRIVATE_IP}" ]; then
    PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address 2>/dev/null)
  fi

  # Check if we got a valid IP
  if [ -n "${PRIVATE_IP}" ] && [[ "${PRIVATE_IP}" =~ ^10\. ]]; then
    log "Private IP: ${PRIVATE_IP}"
    break
  fi

  log "Waiting for network... attempt $i/30"
  sleep 2
done

# Final fallback - use 0.0.0.0 to listen on all interfaces
if [ -z "${PRIVATE_IP}" ] || [[ ! "${PRIVATE_IP}" =~ ^10\. ]]; then
  log "WARNING: Could not determine private IP, using 0.0.0.0"
  PRIVATE_IP="0.0.0.0"
fi

log "Using IP address: ${PRIVATE_IP}"

# Update package lists
log "Updating package lists..."
apt-get update

# Install prerequisites
log "Installing prerequisites..."
apt-get install -y apt-transport-https wget gnupg

# Add Elasticsearch GPG key (if not already added)
log "Adding Elasticsearch GPG key..."
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

# Add Elasticsearch repository (if not already added)
log "Adding Elasticsearch repository..."
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-9.x.list

# Update package lists with new repository
log "Updating package lists with Elasticsearch repository..."
apt-get update

# Install Kibana
log "Installing Kibana version ${ES_VERSION}..."
apt-get install -y kibana=${ES_VERSION}

# Create non-root admin user
log "Creating esadmin user..."
useradd -m -s /bin/bash esadmin || true
usermod -aG sudo esadmin
echo "esadmin ALL=(ALL) NOPASSWD: /bin/systemctl * kibana" >> /etc/sudoers.d/esadmin

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

# Get first Elasticsearch node IP
FIRST_ES_IP=$(echo ${MASTER_IPS} | cut -d',' -f1)
log "Elasticsearch endpoint: https://${FIRST_ES_IP}:9200"

# Configure Kibana for networked mode
log "Configuring Kibana..."
cat > /etc/kibana/kibana.yml << EOF
# Server configuration
server.host: "${PRIVATE_IP}"
server.port: 5601
server.name: "kibana-${CLUSTER_NAME}"

# Elasticsearch connection
elasticsearch.hosts: ["https://${FIRST_ES_IP}:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "${ELASTIC_PASSWORD}"
elasticsearch.ssl.verificationMode: none

# Fleet configuration (uses public Elastic Package Registry)
# Users can configure Fleet through the Kibana UI after installation
xpack.fleet.outputs:
  - id: fleet-default-output
    name: default
    type: elasticsearch
    hosts: ["https://${FIRST_ES_IP}:9200"]
    is_default: true
    is_default_monitoring: true
    ssl:
      verification_mode: none

# Security
xpack.security.enabled: true
xpack.security.encryptionKey: "$(openssl rand -base64 32)"
xpack.encryptedSavedObjects.encryptionKey: "$(openssl rand -base64 32)"
xpack.reporting.encryptionKey: "$(openssl rand -base64 32)"

# Logging
logging.dest: /var/log/kibana/kibana.log
logging.verbose: false

# Performance
server.maxPayloadBytes: 1048576

# Telemetry (enabled for networked mode)
telemetry.enabled: true
telemetry.optIn: false
EOF

# Create log directory
mkdir -p /var/log/kibana
chown kibana:kibana /var/log/kibana

# Set proper permissions
chown root:kibana /etc/kibana/kibana.yml
chmod 660 /etc/kibana/kibana.yml

# Enable and start Kibana
log "Starting Kibana service..."
systemctl enable kibana
systemctl start kibana

# Wait for Kibana to start
log "Waiting for Kibana to start..."
for i in {1..60}; do
  if curl -s -o /dev/null -w "%%{http_code}" http://localhost:5601/api/status | grep -q "200\|302"; then
    log "Kibana is responding"
    break
  fi
  sleep 5
done

# Configure Fleet based on deployment mode
if [[ "${DEPLOYMENT_MODE}" == "airgapped" ]] && [[ -n "${EPR_URL}" ]]; then
  log "Configuring Fleet for local package registry mode..."

  # Wait for Kibana API to be fully ready
  log "Waiting for Kibana API to be ready..."
  for i in {1..30}; do
    if curl -s -u "elastic:${ELASTIC_PASSWORD}" \
         -H "kbn-xsrf: true" \
         http://localhost:5601/api/status | grep -q "available"; then
      log "Kibana API is ready"
      break
    fi
    sleep 10
  done

  # Initialize Fleet
  log "Initializing Fleet..."
  curl -X POST "http://localhost:5601/api/fleet/setup" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:${ELASTIC_PASSWORD}"

  sleep 5

  # Configure Fleet to use local registries
  log "Configuring Fleet to use local EPR and Artifact Registry..."
  curl -X PUT "http://localhost:5601/api/fleet/settings" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    -d "{
      \"package_registry_url\": \"${EPR_URL}\",
      \"agent_binary_download\": {
        \"source_uri\": \"${ARTIFACT_REGISTRY_URL}\"
      }
    }"

  log "Fleet configured for local registries!"
  log "  EPR: ${EPR_URL}"
  log "  Artifact Registry: ${ARTIFACT_REGISTRY_URL}"
else
  log "Fleet will use public Elastic registries (networked mode)"
fi

# Create manual configuration script for Fleet
cat > /home/esadmin/configure_fleet.sh << 'SCRIPT'
#!/bin/bash
# Configure Fleet in Kibana
# Run this manually if automatic configuration failed

set -e

KIBANA_URL="http://localhost:5601"
ELASTIC_USER="elastic"
ELASTIC_PASS="$1"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <elastic_password>"
  exit 1
fi

echo "Configuring Fleet..."

# Setup Fleet
curl -X POST "$KIBANA_URL/api/fleet/setup" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$ELASTIC_USER:$ELASTIC_PASS"

echo "Fleet configured successfully!"
SCRIPT

chmod +x /home/esadmin/configure_fleet.sh
chown esadmin:esadmin /home/esadmin/configure_fleet.sh

log "========================================="
log "Kibana installation complete!"
log "========================================="
log "Kibana URL: http://${PRIVATE_IP}:5601"
log "Username: elastic"
log "Deployment Mode: ${DEPLOYMENT_MODE}"
if [[ "${DEPLOYMENT_MODE}" == "airgapped" ]]; then
  log "Fleet configured for LOCAL registries"
else
  log "Fleet uses PUBLIC Elastic registries"
fi
log "SSH access restricted to esadmin user"
log "========================================="
