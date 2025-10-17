#!/bin/bash
set -e

# NETWORKED Kibana Installation Script
# Installs Kibana from internet repositories

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"
ELASTIC_PASSWORD="${elastic_password}"
CLUSTER_NAME="${cluster_name}"
MASTER_IPS="${master_ips}"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting networked Kibana installation..."

# Get private IP
PRIVATE_IP=${dollar}(hostname -I | awk '{print $$1}')
log "Private IP: $${PRIVATE_IP}"

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
log "Installing Kibana version $${ES_VERSION}..."
apt-get install -y kibana=$${ES_VERSION}

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

# Configure Kibana for networked mode
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

# Fleet configuration (uses public Elastic Package Registry)
# Users can configure Fleet through the Kibana UI after installation
xpack.fleet.outputs:
  - id: fleet-default-output
    name: default
    type: elasticsearch
    hosts: ["https://$${FIRST_ES_IP}:9200"]
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

# Create configuration script for Fleet
cat > /home/esadmin/configure_fleet.sh << 'SCRIPT'
#!/bin/bash
# Configure Fleet in Kibana
# Run this after Kibana is fully operational
# Fleet will use Elastic's public Package Registry (https://epr.elastic.co)

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

# Setup Fleet (will use public Elastic Package Registry by default)
curl -X POST "$KIBANA_URL/api/fleet/setup" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -u "$ELASTIC_USER:$ELASTIC_PASS"

echo "Fleet configured successfully!"
echo "Fleet will use Elastic's public Package Registry: https://epr.elastic.co"
echo "Elastic Agents will download binaries from Elastic's public artifact repository"
SCRIPT

chmod +x /home/esadmin/configure_fleet.sh
chown esadmin:esadmin /home/esadmin/configure_fleet.sh

log "========================================="
log "Networked Kibana installation complete!"
log "========================================="
log "Kibana URL: http://$${PRIVATE_IP}:5601"
log "Username: elastic"
log "Fleet uses public Elastic Package Registry"
log "SSH access restricted to esadmin user"
log "========================================="
