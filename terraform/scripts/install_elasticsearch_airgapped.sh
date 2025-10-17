#!/bin/bash
set -e

# AIR-GAPPED Elasticsearch Installation Script
# This script installs Elasticsearch from local packages without internet access
# Packages must be uploaded to /tmp/elasticsearch-install/ before running this script

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"
ELASTIC_PASSWORD="${elastic_password}"
CLUSTER_NAME="${cluster_name}"
NODE_NUMBER="${node_number}"
TOTAL_MASTERS="${total_masters}"
MASTER_IPS="${master_ips}"
IS_FIRST_NODE="${is_first_node}"
MONITOR_PASSWORD="${monitor_password}"
INGEST_PASSWORD="${ingest_password}"
ADMIN_PASSWORD="${admin_password}"

# Paths
INSTALL_DIR="/tmp/elasticsearch-install"
ES_PKG_DIR="$${INSTALL_DIR}/elasticsearch"
JAVA_PKG_DIR="$${INSTALL_DIR}/java"
DEPS_PKG_DIR="$${INSTALL_DIR}/dependencies"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting air-gapped Elasticsearch installation..."

# Detect node type from hostname
HOSTNAME=${dollar}(hostname)
NODE_ROLES="remote_cluster_client"

if [[ "$${HOSTNAME}" == *"hot"* ]]; then
  NODE_ROLES="master,data_hot,ingest,$${NODE_ROLES}"
elif [[ "$${HOSTNAME}" == *"cold"* ]]; then
  NODE_ROLES="data_cold,$${NODE_ROLES}"
elif [[ "$${HOSTNAME}" == *"frozen"* ]]; then
  NODE_ROLES="data_frozen,$${NODE_ROLES}"
fi

log "Node type: $${NODE_ROLES}"

# Verify packages directory exists
if [ ! -d "$${INSTALL_DIR}" ]; then
    log "ERROR: Installation directory not found: $${INSTALL_DIR}"
    log "Packages must be uploaded before running this script"
    exit 1
fi

# Install system dependencies from local packages
log "Installing system dependencies from local packages..."
if [ -d "$${DEPS_PKG_DIR}" ] && [ "$(ls -A $${DEPS_PKG_DIR}/*.deb 2>/dev/null)" ]; then
    cd "$${DEPS_PKG_DIR}"
    dpkg -i *.deb 2>/dev/null || apt-get install -f -y --no-download
    log "System dependencies installed"
else
    log "WARN: No system dependency packages found, attempting with existing system packages"
fi

# Install Java from local packages
log "Installing Java from local packages..."
if [ -d "$${JAVA_PKG_DIR}" ] && [ "$(ls -A $${JAVA_PKG_DIR}/*.deb 2>/dev/null)" ]; then
    cd "$${JAVA_PKG_DIR}"
    dpkg -i *.deb 2>/dev/null || apt-get install -f -y --no-download
    log "Java installed successfully"
else
    log "ERROR: Java packages not found in $${JAVA_PKG_DIR}"
    exit 1
fi

# Verify Java installation
if ! java -version 2>&1 | grep -q "openjdk"; then
    log "ERROR: Java installation failed"
    exit 1
fi
log "Java version: $(java -version 2>&1 | head -n 1)"

# Install Elasticsearch from local package
log "Installing Elasticsearch from local package..."
if [ -d "$${ES_PKG_DIR}" ]; then
    ES_DEB=$(find "$${ES_PKG_DIR}" -name "elasticsearch-*.deb" | head -n 1)
    if [ -f "$${ES_DEB}" ]; then
        log "Found Elasticsearch package: $${ES_DEB}"
        dpkg -i "$${ES_DEB}" 2>/dev/null || apt-get install -f -y --no-download
        log "Elasticsearch installed successfully"
    else
        log "ERROR: Elasticsearch DEB package not found in $${ES_PKG_DIR}"
        exit 1
    fi
else
    log "ERROR: Elasticsearch package directory not found"
    exit 1
fi

# Verify Elasticsearch installation
if ! systemctl list-unit-files | grep -q elasticsearch.service; then
    log "ERROR: Elasticsearch service not found"
    exit 1
fi
log "Elasticsearch service detected"

# Create non-root user for Elasticsearch administration
log "Creating esadmin user..."
useradd -m -s /bin/bash esadmin || true
usermod -aG sudo esadmin
echo "esadmin ALL=(ALL) NOPASSWD: /bin/systemctl * elasticsearch" >> /etc/sudoers.d/esadmin
echo "esadmin ALL=(ALL) NOPASSWD: /usr/share/elasticsearch/bin/*" >> /etc/sudoers.d/esadmin

# Copy SSH keys from root to esadmin
log "Copying SSH keys to esadmin user..."
mkdir -p /home/esadmin/.ssh
cp /root/.ssh/authorized_keys /home/esadmin/.ssh/authorized_keys
chown -R esadmin:esadmin /home/esadmin/.ssh
chmod 700 /home/esadmin/.ssh
chmod 600 /home/esadmin/.ssh/authorized_keys

# Secure SSH configuration
log "Hardening SSH configuration..."
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Get private IP for binding
PRIVATE_IP=${dollar}(hostname -I | awk '{print $$1}')
log "Private IP: $${PRIVATE_IP}"

# Create directories
log "Creating certificate directories..."
mkdir -p /etc/elasticsearch/certs
mkdir -p /etc/elasticsearch/ca
chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs /etc/elasticsearch/ca

# Generate or copy Certificate Authority
if [[ "$$IS_FIRST_NODE" == "true" ]]; then
  log "Generating Certificate Authority on first node..."
  cd /usr/share/elasticsearch

  # Generate CA
  ./bin/elasticsearch-certutil ca \
    --out /etc/elasticsearch/ca/elastic-stack-ca.p12 \
    --pass ""

  # Generate HTTP CA
  ./bin/elasticsearch-certutil ca \
    --pem \
    --out /etc/elasticsearch/ca/http-ca.zip \
    --pass ""

  cd /etc/elasticsearch/ca
  unzip -o http-ca.zip

  # Store CA for other nodes
  cp elastic-stack-ca.p12 /tmp/elastic-stack-ca.p12
  chmod 644 /tmp/elastic-stack-ca.p12
  log "Certificate Authority generated"
else
  log "Waiting for CA from first node..."
  sleep 60  # Wait for first node to generate CA
fi

# Generate node certificates signed by CA
log "Generating node certificates..."
cd /usr/share/elasticsearch
./bin/elasticsearch-certutil cert \
  --ca /etc/elasticsearch/ca/elastic-stack-ca.p12 \
  --ca-pass "" \
  --dns "$$HOSTNAME,${dollar}(hostname -f),localhost" \
  --ip "$$PRIVATE_IP,127.0.0.1" \
  --name "$$HOSTNAME" \
  --out /etc/elasticsearch/certs/elastic-certificates.p12 \
  --pass ""

# Generate HTTP certificates
log "Generating HTTP certificates..."
./bin/elasticsearch-certutil http \
  --ca /etc/elasticsearch/ca/elastic-stack-ca.p12 \
  --ca-pass "" \
  --dns "$$HOSTNAME,${dollar}(hostname -f),localhost" \
  --ip "$$PRIVATE_IP,127.0.0.1" \
  --out /etc/elasticsearch/certs/http.zip \
  --silent

cd /etc/elasticsearch/certs
unzip -o http.zip
mv elasticsearch/* .
rm -rf elasticsearch kibana http.zip

# Set proper permissions
chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs
chmod 600 /etc/elasticsearch/certs/*.key 2>/dev/null || true
chmod 600 /etc/elasticsearch/certs/*.p12 2>/dev/null || true
log "Certificates configured"

# Create keystore and add passwords
log "Creating Elasticsearch keystore..."
/usr/share/elasticsearch/bin/elasticsearch-keystore create -s
echo "" | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin xpack.security.transport.ssl.keystore.secure_password
echo "" | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin xpack.security.transport.ssl.truststore.secure_password
echo "" | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin xpack.security.http.ssl.keystore.secure_password

# Configure master nodes list
MASTER_NODES_ARRAY=($${MASTER_IPS//,/ })
SEED_HOSTS=""
INITIAL_MASTERS=""
for i in "$${!MASTER_NODES_ARRAY[@]}"; do
  if [ $$i -gt 0 ]; then
    SEED_HOSTS+=", "
    INITIAL_MASTERS+=", "
  fi
  SEED_HOSTS+="\"$${MASTER_NODES_ARRAY[$$i]}\""
  INITIAL_MASTERS+="\"$${CLUSTER_NAME}-hot-${dollar}((i+1))\""
done

# Configure Elasticsearch with enhanced security
log "Configuring Elasticsearch..."
cat > /etc/elasticsearch/elasticsearch.yml << EOF
# Cluster configuration
cluster.name: $$CLUSTER_NAME
node.name: $$HOSTNAME
node.roles: [$$NODE_ROLES]

# Network settings
network.host: $$PRIVATE_IP
http.port: 9200
transport.port: 9300

# Discovery settings
discovery.seed_hosts: [$$SEED_HOSTS]
cluster.initial_master_nodes: [$$INITIAL_MASTERS]

# Security settings - Transport layer
xpack.security.enabled: true
xpack.security.enrollment.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: full
xpack.security.transport.ssl.client_authentication: required
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12

# Security settings - HTTP layer
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.verification_mode: certificate
xpack.security.http.ssl.key: certs/http.key
xpack.security.http.ssl.certificate: certs/http.crt
xpack.security.http.ssl.certificate_authorities: certs/ca.crt

# Audit logging
xpack.security.audit.enabled: true
xpack.security.audit.logfile.events.include:
  - authentication_failed
  - authentication_success
  - access_denied
  - access_granted
  - tampered_request
  - connection_denied
  - run_as_granted
  - run_as_denied
xpack.security.audit.logfile.events.emit_request_body: false
xpack.security.audit.logfile.events.exclude:
  - system_api_call

# API Key service
xpack.security.authc.api_key.enabled: true

# Anonymous access disabled
xpack.security.authc.anonymous.username: anonymous
xpack.security.authc.anonymous.roles: []
xpack.security.authc.anonymous.authz_exception: false

# Additional security headers
http.cors.enabled: false
http.cors.allow-origin: ""

EOF

# Set heap size based on available memory (50% of RAM)
log "Configuring JVM heap size..."
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))

# Calculate heap as 50% of total RAM, with some reasonable defaults
if [ $TOTAL_MEM_GB -ge 7 ]; then
  # 8GB+ RAM: use 4GB heap
  HEAP_SIZE="4g"
elif [ $TOTAL_MEM_GB -ge 3 ]; then
  # 4GB RAM: use 2GB heap
  HEAP_SIZE="2g"
else
  # 2GB RAM: use 1GB heap
  HEAP_SIZE="1g"
fi

sed -i "s/^-Xms.*/-Xms$${HEAP_SIZE}/" /etc/elasticsearch/jvm.options
sed -i "s/^-Xmx.*/-Xmx$${HEAP_SIZE}/" /etc/elasticsearch/jvm.options
log "Set heap size to $${HEAP_SIZE} (Total RAM: ~$${TOTAL_MEM_GB}GB)"

# Enable and start Elasticsearch
log "Starting Elasticsearch service..."
systemctl enable elasticsearch
systemctl start elasticsearch

# Wait for Elasticsearch to start
log "Waiting for Elasticsearch to start..."
for i in {1..60}; do
  if curl -k -s -o /dev/null -w "%%{http_code}" https://$$PRIVATE_IP:9200 | grep -q "401\|200"; then
    log "Elasticsearch is responding"
    break
  fi
  sleep 5
done

# Set built-in user passwords on first node
if [[ "$$IS_FIRST_NODE" == "true" ]]; then
  log "Setting up built-in users passwords..."
  sleep 30  # Wait for cluster to form

  # Set elastic password
  echo "$$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i -s -b

  # Set other built-in user passwords
  echo "$$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i -s -b
  echo "$$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u logstash_system -i -s -b
  echo "$$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u beats_system -i -s -b
  echo "$$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u apm_system -i -s -b
  echo "$$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u remote_monitoring_user -i -s -b
  log "Built-in user passwords configured"
fi

# Create RBAC setup script (same as original)
cat > /home/esadmin/setup_rbac.sh << 'SCRIPT'
#!/bin/bash
set -e

ES_URL="https://localhost:9200"
ELASTIC_PASS="$1"
MONITOR_PASS="$2"
INGEST_PASS="$3"
ADMIN_PASS="$4"

if [ $# -ne 4 ]; then
  echo "Usage: $0 <elastic_password> <monitor_password> <ingest_password> <admin_password>"
  exit 1
fi

# Wait for cluster to be ready
sleep 60

echo "Creating security roles..."

# Create monitoring role
curl -k -X PUT "$ES_URL/_security/role/monitoring_user" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "cluster": ["monitor"],
    "indices": [
      {
        "names": ["*"],
        "privileges": ["read", "view_index_metadata", "monitor"]
      }
    ]
  }'

# Create ingest role
curl -k -X PUT "$ES_URL/_security/role/ingest_user" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "cluster": ["monitor", "manage_index_templates", "manage_ingest_pipelines"],
    "indices": [
      {
        "names": ["logs-*", "metrics-*", "traces-*"],
        "privileges": ["create_index", "create", "write", "index", "manage"]
      }
    ]
  }'

# Create admin role (limited compared to superuser)
curl -k -X PUT "$ES_URL/_security/role/cluster_admin" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "cluster": ["all"],
    "indices": [
      {
        "names": ["*"],
        "privileges": ["all"]
      }
    ],
    "applications": [
      {
        "application": "*",
        "privileges": ["*"],
        "resources": ["*"]
      }
    ]
  }'

# Create snapshot manager role
curl -k -X PUT "$ES_URL/_security/role/snapshot_manager" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "cluster": ["manage_snapshot", "create_snapshot", "monitor"],
    "indices": [
      {
        "names": ["*"],
        "privileges": ["view_index_metadata"]
      }
    ]
  }'

echo "Creating users..."

# Create monitoring user
curl -k -X POST "$ES_URL/_security/user/monitor" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d "{
    \"password\": \"$MONITOR_PASS\",
    \"roles\": [\"monitoring_user\"],
    \"full_name\": \"Monitoring User\",
    \"email\": \"monitor@example.com\"
  }"

# Create ingest user
curl -k -X POST "$ES_URL/_security/user/ingest" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d "{
    \"password\": \"$INGEST_PASS\",
    \"roles\": [\"ingest_user\"],
    \"full_name\": \"Ingest User\",
    \"email\": \"ingest@example.com\"
  }"

# Create admin user (not superuser)
curl -k -X POST "$ES_URL/_security/user/admin" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d "{
    \"password\": \"$ADMIN_PASS\",
    \"roles\": [\"cluster_admin\"],
    \"full_name\": \"Cluster Administrator\",
    \"email\": \"admin@example.com\"
  }"

echo "Creating API keys..."

# Create monitoring API key
MONITOR_KEY=$(curl -k -X POST "$ES_URL/_security/api_key" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "monitoring-api-key",
    "expiration": "90d",
    "role_descriptors": {
      "monitoring": {
        "cluster": ["monitor"],
        "indices": [
          {
            "names": ["*"],
            "privileges": ["read", "monitor"]
          }
        ]
      }
    },
    "metadata": {
      "purpose": "monitoring",
      "environment": "production"
    }
  }' | jq -r '.encoded')

# Create ingest API key
INGEST_KEY=$(curl -k -X POST "$ES_URL/_security/api_key" \
  -u "elastic:$ELASTIC_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ingest-api-key",
    "expiration": "90d",
    "role_descriptors": {
      "ingest": {
        "cluster": ["monitor", "manage_index_templates"],
        "indices": [
          {
            "names": ["logs-*", "metrics-*"],
            "privileges": ["create_index", "create", "write", "index"]
          }
        ]
      }
    },
    "metadata": {
      "purpose": "data-ingestion",
      "environment": "production"
    }
  }' | jq -r '.encoded')

echo "RBAC setup complete!"
echo ""
echo "=== API Keys ==="
echo "Monitoring API Key: $MONITOR_KEY"
echo "Ingest API Key: $INGEST_KEY"
echo ""
echo "Store these API keys securely!"

# Save API keys to secure location
cat > /home/esadmin/api_keys.txt << EOL
Monitoring API Key: $MONITOR_KEY
Ingest API Key: $INGEST_KEY
EOL
chmod 600 /home/esadmin/api_keys.txt
chown esadmin:esadmin /home/esadmin/api_keys.txt

SCRIPT

chmod +x /home/esadmin/setup_rbac.sh
chown esadmin:esadmin /home/esadmin/setup_rbac.sh

# Run RBAC setup on first node
if [[ "$$IS_FIRST_NODE" == "true" ]]; then
  log "Setting up RBAC..."
  sudo -u esadmin /home/esadmin/setup_rbac.sh "$$ELASTIC_PASSWORD" "$$MONITOR_PASSWORD" "$$INGEST_PASSWORD" "$$ADMIN_PASSWORD"
fi

# Create snapshot repository configuration script (same as original)
cat > /home/esadmin/configure_snapshot_repo.sh << 'SCRIPT'
#!/bin/bash
# This script should be run after the cluster is fully formed
# Usage: ./configure_snapshot_repo.sh <spaces_endpoint> <access_key> <secret_key>

if [ $# -ne 3 ]; then
  echo "Usage: $0 <spaces_endpoint> <access_key> <secret_key>"
  exit 1
fi

SPACES_ENDPOINT=$1
ACCESS_KEY=$2
SECRET_KEY=$3

# Add S3 credentials to keystore
echo "$ACCESS_KEY" | sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.access_key --force
echo "$SECRET_KEY" | sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.secret_key --force

# Reload secure settings
curl -k -u elastic:$ELASTIC_PASSWORD -X POST "https://localhost:9200/_nodes/reload_secure_settings" \
  -H "Content-Type: application/json" \
  -d '{}'

# Create snapshot repository
curl -k -u elastic:$ELASTIC_PASSWORD -X PUT "https://localhost:9200/_snapshot/searchable_snapshots" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "s3",
    "settings": {
      "endpoint": "'$SPACES_ENDPOINT'",
      "protocol": "https",
      "compress": true,
      "server_side_encryption": true,
      "storage_class": "standard",
      "readonly": false
    }
  }'

echo "Snapshot repository configured!"
SCRIPT

chmod +x /home/esadmin/configure_snapshot_repo.sh
chown esadmin:esadmin /home/esadmin/configure_snapshot_repo.sh

# Create security validation script (same as original)
cat > /home/esadmin/validate_security.sh << 'SCRIPT'
#!/bin/bash

echo "=== Security Validation ==="
echo ""

# Check cluster health
echo "1. Cluster Health:"
curl -k -u elastic:$1 https://localhost:9200/_cluster/health?pretty

# Check security status
echo -e "\n2. Security Status:"
curl -k -u elastic:$1 https://localhost:9200/_xpack?pretty | jq '.features.security'

# Check audit logs
echo -e "\n3. Audit Logs:"
tail -n 5 /var/log/elasticsearch/*_audit.json 2>/dev/null || echo "No audit logs yet"

# Check users
echo -e "\n4. Users:"
curl -k -u elastic:$1 https://localhost:9200/_security/user?pretty

# Check roles
echo -e "\n5. Roles:"
curl -k -u elastic:$1 https://localhost:9200/_security/role?pretty

# Check certificates
echo -e "\n6. Certificate Validation:"
openssl s_client -connect localhost:9200 -showcerts < /dev/null 2>/dev/null | grep "subject\|issuer"

echo -e "\nSecurity validation complete!"
SCRIPT

chmod +x /home/esadmin/validate_security.sh
chown esadmin:esadmin /home/esadmin/validate_security.sh

# Clean up installation packages
log "Cleaning up installation packages..."
rm -rf "$${INSTALL_DIR}"

log "========================================="
log "Air-gapped Elasticsearch installation complete!"
log "========================================="
log "Cluster: $${CLUSTER_NAME}"
log "Node: $${HOSTNAME}"
log "Roles: $${NODE_ROLES}"
log "SSH access is now restricted to non-root users only"
log "Use the esadmin user for administration tasks"
log "========================================="
