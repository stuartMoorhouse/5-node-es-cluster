#!/bin/bash
set -e

# Variables passed from Terraform
ES_VERSION="${elasticsearch_version}"
ELASTIC_PASSWORD="${elastic_password}"
CLUSTER_NAME="${cluster_name}"

# Detect node type from hostname
HOSTNAME=$(hostname)
NODE_ROLE="data_hot"

if [[ "$HOSTNAME" == *"cold"* ]]; then
  NODE_ROLE="data_cold"
elif [[ "$HOSTNAME" == *"frozen"* ]]; then
  NODE_ROLE="data_frozen"
fi

# Update system
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Install Java (Elasticsearch 8.x includes bundled JDK, but having system Java is useful)
apt-get install -y openjdk-17-jre-headless

# Add Elasticsearch repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-9.x.list

# Install Elasticsearch
apt-get update
apt-get install -y elasticsearch=$ES_VERSION

# Get private IP for binding
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Configure Elasticsearch
cat > /etc/elasticsearch/elasticsearch.yml << EOF
cluster.name: $CLUSTER_NAME
node.name: $HOSTNAME
node.roles: [$NODE_ROLE, remote_cluster_client]

# Network settings
network.host: $PRIVATE_IP
http.port: 9200
transport.port: 9300

# Discovery settings (will be updated after all nodes are created)
discovery.seed_hosts: []
cluster.initial_master_nodes: []

# Security
xpack.security.enabled: true
xpack.security.enrollment.enabled: true
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: /etc/elasticsearch/certs/http.key
xpack.security.http.ssl.certificate: /etc/elasticsearch/certs/http.crt
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.key: /etc/elasticsearch/certs/transport.key
xpack.security.transport.ssl.certificate: /etc/elasticsearch/certs/transport.crt

# Heap size based on node type
EOF

# Set heap size based on node type
if [[ "$NODE_ROLE" == "data_hot" ]]; then
  # 4GB heap for 8GB nodes (50% of RAM)
  sed -i 's/^-Xms.*/-Xms4g/' /etc/elasticsearch/jvm.options
  sed -i 's/^-Xmx.*/-Xmx4g/' /etc/elasticsearch/jvm.options
else
  # 1GB heap for 2GB nodes (50% of RAM)
  sed -i 's/^-Xms.*/-Xms1g/' /etc/elasticsearch/jvm.options
  sed -i 's/^-Xmx.*/-Xmx1g/' /etc/elasticsearch/jvm.options
fi

# Create certificates directory
mkdir -p /etc/elasticsearch/certs

# Generate self-signed certificates (in production, use proper CA)
openssl req -x509 -newkey rsa:4096 -keyout /etc/elasticsearch/certs/http.key \
  -out /etc/elasticsearch/certs/http.crt -days 365 -nodes \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=$HOSTNAME"

openssl req -x509 -newkey rsa:4096 -keyout /etc/elasticsearch/certs/transport.key \
  -out /etc/elasticsearch/certs/transport.crt -days 365 -nodes \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=$HOSTNAME"

# Set proper permissions
chown -R elasticsearch:elasticsearch /etc/elasticsearch/certs
chmod 600 /etc/elasticsearch/certs/*.key

# Set the elastic user password
echo "$ELASTIC_PASSWORD" | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i -s

# Enable and start Elasticsearch
systemctl enable elasticsearch
systemctl start elasticsearch

# Wait for Elasticsearch to start
sleep 30

# Create snapshot repository configuration script
cat > /home/ubuntu/configure_snapshot_repo.sh << 'SCRIPT'
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

curl -k -u elastic:$ELASTIC_PASSWORD -X PUT "https://localhost:9200/_snapshot/searchable_snapshots" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "s3",
    "settings": {
      "endpoint": "'$SPACES_ENDPOINT'",
      "access_key": "'$ACCESS_KEY'",
      "secret_key": "'$SECRET_KEY'",
      "compress": true,
      "server_side_encryption": true
    }
  }'
SCRIPT

chmod +x /home/ubuntu/configure_snapshot_repo.sh

echo "Elasticsearch installation complete!"