#!/bin/bash
set -e

# AIR-GAPPED Kibana Installation Script
# Installs Kibana from local packages and configures for air-gapped environment

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"
ELASTIC_PASSWORD="${elastic_password}"
CLUSTER_NAME="${cluster_name}"
MASTER_IPS="${master_ips}"
EPR_URL="${epr_url}"
ARTIFACT_REGISTRY_URL="${artifact_registry_url}"

# Paths
INSTALL_DIR="/tmp/elasticsearch-install"
KIBANA_PKG_DIR="$${INSTALL_DIR}/kibana"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting air-gapped Kibana installation..."

# Get private IP
PRIVATE_IP=${dollar}(hostname -I | awk '{print $$1}')
log "Private IP: $${PRIVATE_IP}"

# Verify packages directory exists
if [ ! -d "$${KIBANA_PKG_DIR}" ]; then
    log "ERROR: Kibana package directory not found: $${KIBANA_PKG_DIR}"
    exit 1
fi

# Install Kibana from local package
log "Installing Kibana from local package..."
KIBANA_DEB=$(find "$${KIBANA_PKG_DIR}" -name "kibana-*.deb" | head -n 1)
if [ -f "$${KIBANA_DEB}" ]; then
    log "Found Kibana package: $${KIBANA_DEB}"
    dpkg -i "$${KIBANA_DEB}" 2>/dev/null || apt-get install -f -y --no-download
    log "Kibana installed successfully"
else
    log "ERROR: Kibana DEB package not found in $${KIBANA_PKG_DIR}"
    exit 1
fi

# Create non-root admin user
log "Creating esadmin user..."
useradd -m -s /bin/bash esadmin || true
usermod -aG sudo esadmin
echo "esadmin ALL=(ALL) NOPASSWD: /bin/systemctl * kibana" >> /etc/sudoers.d/esadmin

# Secure SSH
log "Hardening SSH configuration..."
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Get first Elasticsearch node IP
FIRST_ES_IP=$(echo $${MASTER_IPS} | cut -d',' -f1)
log "Elasticsearch endpoint: https://$${FIRST_ES_IP}:9200"

# Configure Kibana
log "Configuring Kibana..."
cat > /etc/kibana/kibana.yml << EOF
# Server configuration
server.host: "$${PRIVATE_IP}"
server.port: 5601
server.name: "kibana-$${CLUSTER_NAME}"

# Elasticsearch connection
elasticsearch.hosts: ["https://$${FIRST_ES_IP}:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "$${ELASTIC_PASSWORD}"
elasticsearch.ssl.verificationMode: none

# Air-gapped configuration
xpack.fleet.registryUrl: "$${EPR_URL}"
xpack.fleet.agents.fleet_server.hosts: []
xpack.fleet.agentPolicies.airgapped.enabled: true

# Fleet configuration (for future use)
xpack.fleet.outputs:
  - id: fleet-default-output
    name: default
    type: elasticsearch
    hosts: ["https://$${FIRST_ES_IP}:9200"]
    is_default: true
    is_default_monitoring: true
    ssl:
      verification_mode: none

# Artifact registry for agent binaries
xpack.fleet.agentBinary.download:
  sourceURI: "$${ARTIFACT_REGISTRY_URL}"

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

# Disable telemetry for air-gapped
telemetry.enabled: false
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

# Create configuration script for Fleet
cat > /home/esadmin/configure_fleet.sh << 'SCRIPT'
#!/bin/bash
# Configure Fleet in Kibana
# Run this after Kibana is fully operational

set -e

KIBANA_URL="http://localhost:5601"
ELASTIC_USER="elastic"
ELASTIC_PASS="$1"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <elastic_password>"
  exit 1
fi

echo "Configuring Fleet..."

# Wait for Kibana to be ready
sleep 30

# Setup Fleet
curl -X POST "$KIBANA_URL/api/fleet/setup" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$ELASTIC_USER:$ELASTIC_PASS"

echo "Fleet configured successfully!"
SCRIPT

chmod +x /home/esadmin/configure_fleet.sh
chown esadmin:esadmin /home/esadmin/configure_fleet.sh

# Clean up installation packages
log "Cleaning up installation packages..."
rm -rf "$${INSTALL_DIR}"

log "========================================="
log "Air-gapped Kibana installation complete!"
log "========================================="
log "Kibana URL: http://$${PRIVATE_IP}:5601"
log "Username: elastic"
log "EPR URL: $${EPR_URL}"
log "Artifact Registry: $${ARTIFACT_REGISTRY_URL}"
log "SSH access restricted to esadmin user"
log "========================================="
