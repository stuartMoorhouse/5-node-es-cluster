# Self-hosted Elastic Enterprise Cluster Setup Guide for Security Use Cases

**Last Updated**: Current configuration implements comprehensive security controls

## Implementation Status
✅ **FULLY SECURED** - This Terraform configuration now implements enterprise-grade security:
- Certificate Authority with proper certificate chain
- Role-Based Access Control (RBAC) with multiple user levels
- Master-eligible nodes for cluster stability
- Audit logging for compliance
- API key management for programmatic access
- Restrictive firewall rules (principle of least privilege)
- Non-root SSH access only
- Keystore for sensitive data protection

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Enterprise License Activation](#enterprise-license-activation)
3. [Cluster Security - TLS Certificates](#cluster-security---tls-certificates)
4. [API Keys Configuration](#api-keys-configuration)
5. [Index Mapping](#index-mapping)
6. [Index Lifecycle Management (ILM)](#index-lifecycle-management-ilm)
7. [Customizing Built-in logs-* Templates with Custom ILM Policies](#customizing-built-in-logs--templates-with-custom-ilm-policies)
8. [Data Views](#data-views)
9. [Kibana Spaces](#kibana-spaces)
10. [Fleet Configuration](#fleet-configuration)
11. [Elastic Agent Deployment](#elastic-agent-deployment)
12. [References](#references)

## Current Implementation Security Features

### Automated Security Setup via Terraform

Our Terraform configuration automatically implements:

#### 1. Authentication & Authorization
- **Multiple User Accounts**:
  - `elastic` - Superuser (use sparingly)
  - `admin` - Cluster administrator (non-superuser)
  - `monitor` - Read-only monitoring access
  - `ingest` - Data ingestion only
- **API Keys** - Generated automatically for programmatic access
- **Password Management** - Secure random passwords generated via Terraform

#### 2. Network Security
- **VPC Isolation** - Private network for inter-node communication
- **Restrictive Firewalls**:
  - Inbound: Only allows SSH from specific IPs, ES access via load balancer
  - Outbound: Limited to essential services (HTTPS, DNS, NTP, internal cluster)
- **Load Balancer** - Single entry point for client connections
- **SSH Hardening**:
  - Root login disabled
  - Non-root `esadmin` user with sudo privileges
  - Separate SSH access control list

#### 3. Encryption
- **Transport Layer Security** - Full TLS between nodes with certificate verification
- **HTTP Layer Security** - HTTPS enabled for all client connections
- **Certificate Authority** - Centralized CA with proper certificate chain
- **Keystore Protection** - Sensitive data stored in Elasticsearch keystore

#### 4. Cluster Architecture
- **Master Eligible Nodes** - 3 hot nodes serve as master-eligible for quorum
- **Node Roles**:
  - Hot nodes: master, data_hot, ingest
  - Cold node: data_cold only
  - Frozen node: data_frozen only
- **Proper Discovery** - Configured seed hosts and initial master nodes

#### 5. Compliance & Monitoring
- **Audit Logging** - Comprehensive security event logging
- **Authentication Tracking** - Failed/successful login attempts logged
- **Access Control Logging** - Granted/denied access recorded
- **Security Validation Scripts** - Built-in verification tools

### Post-Deployment Security Tasks

After running `terraform apply`, complete these tasks:

1. **Retrieve Credentials**:
   ```bash
   terraform output -raw elasticsearch_password  # Elastic superuser
   terraform output -raw admin_password         # Admin user
   terraform output -raw monitor_password       # Monitor user
   terraform output -raw ingest_password        # Ingest user
   ```

2. **Access Nodes** (via non-root user):
   ```bash
   ssh esadmin@<node-ip>
   ```

3. **Configure Snapshot Repository**:
   ```bash
   # On any node as esadmin
   ./configure_snapshot_repo.sh <spaces_endpoint> <access_key> <secret_key>
   ```

4. **Validate Security**:
   ```bash
   # On any node as esadmin
   ./validate_security.sh <elastic_password>
   ```

5. **Retrieve API Keys**:
   ```bash
   # SSH to first hot node
   ssh esadmin@<first-hot-node-ip>
   cat /home/esadmin/api_keys.txt
   ```

## Prerequisites

### Hardware Requirements
For production deployments, each Elasticsearch node should have:
- **Memory:** Minimum 8GB RAM, recommended 16-64GB depending on workload
- **CPU:** Multi-core processors (4-8 cores recommended)
- **Storage:** SSD storage recommended for better performance
- **Network:** Gigabit ethernet or better

For high availability, deploy at least 3 master-eligible nodes across different physical hosts or availability zones.

### Software Requirements
- **Operating System:** Ubuntu 18.04+ or Ubuntu 20.04+ (LTS versions recommended)
- **Java:** Elasticsearch includes a bundled OpenJDK. If using your own JVM, use a supported version
- **Kernel:** Linux kernel 4.15 or later recommended
- **File System:** XFS recommended for better performance, ext4 also supported

### Network Requirements
- Ensure all Elasticsearch nodes can communicate on ports 9200 (HTTP) and 9300 (transport)
- Fleet Server requires port 8220
- Kibana typically runs on port 5601

**Documentation:** https://www.elastic.co/guide/en/elasticsearch/reference/current/install-elasticsearch.html

## Enterprise License Activation

### Step 1: Obtain Enterprise License
To enable all Enterprise features, you need to purchase an Enterprise subscription. Contact Elastic sales to obtain your license file.

### Step 2: Install License

#### Via Kibana UI:
1. Navigate to **Stack Management > License Management**
2. Click **Update license**
3. Upload your license JSON file

#### Via REST API:
```bash
POST /_license
{
  "licenses": [{
    "uid": "your-license-uid",
    "type": "enterprise",
    "issue_date_in_millis": 1234567890,
    "expiry_date_in_millis": 1234567890,
    "max_nodes": 100,
    "issued_to": "Your Organization",
    "issuer": "Elastic",
    "signature": "your-license-signature"
  }]
}
```

### Step 3: Verify License
```bash
GET /_license
```

The Enterprise subscription tier provides access to all features including advanced security, machine learning, and cross-cluster replication capabilities.

**Documentation:** https://www.elastic.co/guide/en/kibana/current/managing-licenses.html

## Cluster Security - TLS Certificates

### ✅ IMPLEMENTED: Automatic Certificate Management

The Terraform configuration now automatically handles all certificate operations:

1. **Certificate Authority Generation** - First node creates the CA
2. **Node Certificate Generation** - Each node gets certificates signed by the CA
3. **Proper Certificate Chain** - Full verification mode enabled
4. **Automatic Distribution** - Certificates configured on all nodes

### Manual Verification (Post-Deployment)

To verify certificates are properly configured:

```bash
# SSH to any node (as esadmin user)
ssh esadmin@<node-ip>

# Check certificate chain
openssl s_client -connect localhost:9200 -showcerts

# Validate certificate details
sudo openssl x509 -in /etc/elasticsearch/certs/http.crt -text -noout
```

### Step 2: Generate Node Certificates
Create certificates for each node in your cluster.

```bash
# Generate certificates signed by CA
./bin/elasticsearch-certutil cert --ca elastic-stack-ca.p12
# Output: elastic-certificates.p12

# For production, generate individual certificates per node:
./bin/elasticsearch-certutil cert \
  --ca elastic-stack-ca.p12 \
  --dns node1.example.com \
  --ip 192.168.1.1 \
  --name node1
```

### Step 3: Deploy Certificates
Copy certificates to the Elasticsearch configuration directory on each node:

```bash
# Create certs directory
mkdir /etc/elasticsearch/certs

# Copy certificates
cp elastic-certificates.p12 /etc/elasticsearch/certs/
chmod 640 /etc/elasticsearch/certs/elastic-certificates.p12
chown root:elasticsearch /etc/elasticsearch/certs/elastic-certificates.p12
```

### Step 4: Configure Transport Security
Edit `/etc/elasticsearch/elasticsearch.yml` on all nodes:

```yaml
# Enable security features
xpack.security.enabled: true

# Transport layer security (node-to-node communication)
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.client_authentication: required
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12
```

### Step 5: Configure HTTP Security (HTTPS)
Generate HTTP layer certificates:

```bash
# Generate HTTP certificates
./bin/elasticsearch-certutil http

# This will prompt you for:
# - Whether to generate a CSR (answer 'n' for self-signed)
# - Whether to use existing CA (answer 'y' and provide path to elastic-stack-ca.p12)
# - Hostnames and IPs for the certificates
```

Add to `/etc/elasticsearch/elasticsearch.yml`:

```yaml
# HTTP layer security (client-to-node communication)
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/http.p12
xpack.security.http.ssl.truststore.path: certs/http.p12
```

### Step 6: Store Certificate Passwords
Store certificate passwords securely:

```bash
# Add passwords to keystore
./bin/elasticsearch-keystore add xpack.security.transport.ssl.keystore.secure_password
./bin/elasticsearch-keystore add xpack.security.transport.ssl.truststore.secure_password
./bin/elasticsearch-keystore add xpack.security.http.ssl.keystore.secure_password
./bin/elasticsearch-keystore add xpack.security.http.ssl.truststore.secure_password
```

### Step 7: Set Built-in User Passwords
After starting Elasticsearch with security enabled:

```bash
# Auto-generate passwords
./bin/elasticsearch-setup-passwords auto

# Or set them interactively
./bin/elasticsearch-setup-passwords interactive
```

**Documentation:** https://www.elastic.co/guide/en/elasticsearch/reference/current/security-basic-setup.html

## API Keys Configuration

### Step 1: Enable API Key Service
The API key service is enabled by default when security is enabled. To explicitly configure:

```yaml
# In elasticsearch.yml
xpack.security.authc.api_key.enabled: true
```

### Step 2: Create API Keys for Security Monitoring

```bash
POST /_security/api_key
{
  "name": "security-monitoring-key",
  "expiration": "30d",
  "role_descriptors": {
    "security-reader": {
      "cluster": ["monitor", "manage_index_templates"],
      "indices": [
        {
          "names": [
            "logs-*",
            "metrics-*",
            ".siem-signals-*",
            ".alerts-security.*"
          ],
          "privileges": ["read", "write", "create_index", "view_index_metadata"]
        }
      ]
    }
  },
  "metadata": {
    "purpose": "security-monitoring",
    "team": "soc",
    "created_by": "admin"
  }
}
```

### Step 3: Create API Key for Fleet Server

```bash
POST /_security/api_key
{
  "name": "fleet-server-api-key",
  "role_descriptors": {
    "fleet-server": {
      "cluster": ["monitor", "manage_security"],
      "indices": [
        {
          "names": [".fleet-*"],
          "privileges": ["all"]
        },
        {
          "names": ["logs-*", "metrics-*"],
          "privileges": ["auto_configure", "create_doc"]
        }
      ]
    }
  }
}
```

### Step 4: Use API Keys
Use the encoded API key in requests:

```bash
curl -X GET "https://localhost:9200/_cluster/health" \
  -H "Authorization: ApiKey <encoded-api-key>" \
  --cacert /path/to/ca.crt
```

**Documentation:** https://www.elastic.co/guide/en/elasticsearch/reference/current/security-api-create-api-key.html

## Index Mapping

### Step 1: Create Index Template for Security Events

```bash
PUT _index_template/security-events-template
{
  "index_patterns": ["security-events-*", "logs-security-*"],
  "priority": 200,
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "index.lifecycle.name": "security-ilm-policy",
      "index.lifecycle.rollover_alias": "security-events"
    },
    "mappings": {
      "properties": {
        "@timestamp": {
          "type": "date"
        },
        "event": {
          "properties": {
            "kind": { "type": "keyword" },
            "category": { "type": "keyword" },
            "type": { "type": "keyword" },
            "outcome": { "type": "keyword" },
            "severity": { "type": "long" }
          }
        },
        "host": {
          "properties": {
            "name": { "type": "keyword" },
            "ip": { "type": "ip" },
            "hostname": { "type": "keyword" }
          }
        },
        "source": {
          "properties": {
            "ip": { "type": "ip" },
            "port": { "type": "long" },
            "address": { "type": "keyword" }
          }
        },
        "destination": {
          "properties": {
            "ip": { "type": "ip" },
            "port": { "type": "long" },
            "address": { "type": "keyword" }
          }
        },
        "threat": {
          "properties": {
            "indicator": {
              "type": "nested",
              "properties": {
                "ip": { "type": "ip" },
                "domain": { "type": "keyword" },
                "matched": { "type": "boolean" },
                "type": { "type": "keyword" }
              }
            }
          }
        },
        "user": {
          "properties": {
            "name": { "type": "keyword" },
            "domain": { "type": "keyword" },
            "id": { "type": "keyword" }
          }
        }
      }
    }
  }
}
```

### Step 2: Create Bootstrap Index

```bash
PUT security-events-000001
{
  "aliases": {
    "security-events": {
      "is_write_index": true
    }
  }
}
```

**Documentation:** https://www.elastic.co/guide/en/elasticsearch/reference/current/index-templates.html

## Index Lifecycle Management (ILM)

### Step 1: Create ILM Policy for Security Data

```bash
PUT _ilm/policy/security-ilm-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50GB",
            "max_age": "7d",
            "max_docs": 50000000
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "set_priority": {
            "priority": 50
          },
          "readonly": {}
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": {
            "priority": 0
          },
          "searchable_snapshot": {
            "snapshot_repository": "cold-snapshot-repo"
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

### Step 2: Configure ILM Settings

```bash
# Set ILM poll interval (how often ILM checks for phase transitions)
PUT _cluster/settings
{
  "persistent": {
    "indices.lifecycle.poll_interval": "10m"
  }
}
```

### Step 3: Apply Policy to Existing Indices

```bash
PUT security-events-*/_settings
{
  "index.lifecycle.name": "security-ilm-policy"
}
```

**Documentation:** https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html

## Customizing Built-in logs-* Templates with Custom ILM Policies

### Best Practice Overview

Elasticsearch provides managed templates and ILM policies for data streams like `logs-*-*`. To customize these without breaking managed templates, follow the recommended `logs@custom` component template approach.

**Important Warning:** Never edit managed policies directly. Changes to managed policies might be rolled back or overwritten during Elasticsearch updates.

### Step 1: Create a Custom ILM Policy

#### Via Kibana UI (Recommended):
1. Navigate to **Stack Management > Index Lifecycle Policies**
2. Toggle **Include managed system policies** (to see `logs@lifecycle`)
3. Select the `logs@lifecycle` policy
4. Review the default settings:
   - Rollover when primary shard reaches 50GB or index is 30 days old
   - Configurable hot, warm, cold, frozen, and delete phases
5. Click **Edit policy**
6. Toggle **Save as new policy**
7. Provide a new name (e.g., `logs-custom`)
8. Customize the phases as needed:

```bash
# Example custom policy settings
PUT _ilm/policy/logs-custom
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50GB",
            "max_age": "30d"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "30d",
        "actions": {
          "set_priority": {
            "priority": 50
          },
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

#### Via REST API:
If you copied a managed policy, use the API to modify the `_meta.managed` parameter:

```bash
PUT _ilm/policy/logs-custom
{
  "policy": {
    "_meta": {
      "managed": false,
      "description": "Custom ILM policy for logs data streams"
    },
    "phases": {
      "hot": { /* ... */ },
      "warm": { /* ... */ },
      "delete": { /* ... */ }
    }
  }
}
```

### Step 2: Create the logs@custom Component Template

The `logs@custom` component template allows you to customize settings of managed index templates without overriding them. This template is automatically picked up by the `logs` index template.

**Prerequisites:** Available in Elasticsearch 8.13 and later.

#### Via Kibana UI:
1. Navigate to **Stack Management > Index Management > Component Templates**
2. Click **Create component template**
3. Under **Logistics**, name the component template: `logs@custom`
4. Add a description: "Custom ILM policy and settings for logs data streams"
5. Under **Index settings**, add your custom ILM policy:

```json
{
  "index": {
    "lifecycle": {
      "name": "logs-custom"
    }
  }
}
```

6. (Optional) Add any other custom settings:

```json
{
  "index": {
    "lifecycle": {
      "name": "logs-custom"
    },
    "number_of_replicas": 1,
    "codec": "best_compression"
  }
}
```

7. Click **Next** through mappings and aliases (leave default or customize)
8. Review and click **Create component template**

#### Via REST API:

```bash
PUT _component_template/logs@custom
{
  "template": {
    "settings": {
      "index": {
        "lifecycle": {
          "name": "logs-custom"
        }
      }
    }
  },
  "_meta": {
    "description": "Custom ILM policy for all logs data streams"
  }
}
```

### Step 3: Verify the Component Template is Applied

Check that the `logs@custom` component template is properly integrated:

```bash
# View the logs index template
GET _index_template/logs

# Verify logs@custom appears in the composed_of array
# Expected output should include:
# "composed_of": [
#   "logs@settings",
#   "logs@custom",     <-- Should appear here
#   "ecs@mappings",
#   ...
# ]
```

Or verify via Kibana:
1. Navigate to **Stack Management > Index Management > Index Templates**
2. Click on the `logs` index template
3. Verify `logs@custom` appears in the **Component templates** list

### Step 4: Apply Changes to Existing Data Streams

**Important:** New ILM policies only apply to newly created indices. You have two options:

#### Option A: Wait for Automatic Rollover
Wait for natural rollover to occur (when indices reach 50GB or 30 days old, based on your policy).

#### Option B: Force Immediate Rollover (Recommended)
Force rollover on existing data streams to immediately apply the new policy:

```bash
# List all logs data streams
GET _data_stream/logs-*

# Force rollover on specific data stream
POST /logs-system.auth-default/_rollover/

# Force rollover on all logs data streams (use with caution)
# You can script this or use Kibana Dev Tools
POST /logs-system.syslog-default/_rollover/
POST /logs-elastic_agent-default/_rollover/
POST /logs-elastic_agent.filebeat-default/_rollover/
# ... repeat for each data stream
```

To rollover all logs data streams programmatically:

```bash
# Get list of all logs data streams and rollover each
curl -X GET "https://localhost:9200/_data_stream/logs-*" | \
  jq -r '.data_streams[].name' | \
  while read ds; do
    echo "Rolling over: $ds"
    curl -X POST "https://localhost:9200/$ds/_rollover/"
  done
```

### Step 5: Verify the Policy is Applied

Check that new indices are using your custom policy:

```bash
# Check a specific index's ILM policy
GET logs-system.auth-default-000002/_settings

# Should show:
# "settings": {
#   "index": {
#     "lifecycle": {
#       "name": "logs-custom"
#     }
#   }
# }

# View ILM explain for detailed policy execution status
GET logs-*/_ilm/explain
```

### Alternative: Apply Custom ILM to Specific Integration

If you want to apply a custom ILM policy to only specific integrations (not all logs), create a custom index template instead:

```bash
PUT _index_template/logs-system-custom
{
  "index_patterns": ["logs-system.*-*"],
  "priority": 250,
  "composed_of": [
    "logs@settings",
    "logs@mappings"
  ],
  "template": {
    "settings": {
      "index.lifecycle.name": "logs-system-custom"
    }
  }
}
```

**Note:** Set priority higher than the default `logs` template (typically 200) to ensure your custom template takes precedence.

### Monitoring and Troubleshooting

Monitor ILM policy execution:

```bash
# Check ILM status
GET _ilm/status

# View detailed ILM explain for all logs indices
GET logs-*/_ilm/explain?human

# Check for ILM errors
GET logs-*/_ilm/explain?only_errors=true

# View ILM history for a specific index
GET logs-system.auth-default-000001
```

### Common Pitfalls to Avoid

1. **Editing Managed Policies:** Always create a new policy rather than editing `logs@lifecycle` directly
2. **Forgetting to Rollover:** Remember that existing indices keep their old policy until rollover
3. **Component Template Naming:** The template must be named exactly `logs@custom` (for metrics, use `metrics@custom`)
4. **Priority Conflicts:** If using custom index templates, ensure priority is higher than default templates
5. **Version Requirements:** The `*@custom` component template feature requires Elasticsearch 8.13+

**Documentation:**
- https://www.elastic.co/guide/en/elasticsearch/reference/current/example-using-index-lifecycle-policy.html
- https://www.elastic.co/guide/en/fleet/current/data-streams-ilm-tutorial.html

## Data Views

### Step 1: Create Data View in Kibana

1. Navigate to **Stack Management > Data Views**
2. Click **Create data view**
3. Configure the data view:

```json
{
  "name": "Security Events",
  "title": "security-*",
  "timeFieldName": "@timestamp",
  "fields": {
    "source.ip": {
      "customLabel": "Source IP Address"
    },
    "threat.indicator.matched": {
      "customLabel": "Threat Match"
    }
  }
}
```

### Step 2: Add Runtime Fields
Runtime fields allow you to create calculated fields at query time:

1. In the Data View editor, click **Add field**
2. Choose **Runtime field**
3. Add a threat score calculator:

```javascript
// Painless script for runtime field
if (doc.containsKey('threat.indicator.confidence') && 
    doc['threat.indicator.confidence'].size() > 0) {
  emit(doc['threat.indicator.confidence'].value * 100);
} else {
  emit(0);
}
```

### Step 3: Configure Field Formatters

1. Select a field in the Data View
2. Set format type (URL, Bytes, Duration, etc.)
3. For IP addresses, create URL template:

```
https://your-threatintel.local/lookup/{{value}}
```

**Documentation:** https://www.elastic.co/guide/en/kibana/current/data-views.html

## Kibana Spaces

### Step 1: Enable and Configure Spaces

Spaces are enabled by default. Configure in `/etc/kibana/kibana.yml`:

```yaml
# Maximum number of spaces
xpack.spaces.maxSpaces: 100
```

### Step 2: Create Security Operations Space

1. Navigate to **Stack Management > Spaces**
2. Click **Create space**
3. Configure:

```json
{
  "id": "security-ops",
  "name": "Security Operations",
  "description": "SOC team operational space",
  "color": "#FF0000",
  "initials": "SO",
  "disabledFeatures": ["dev_tools"],
  "imageUrl": ""
}
```

### Step 3: Set Space-specific Settings

In **Stack Management > Advanced Settings** (while in the Security Operations space):

```yaml
# Default landing page for this space
defaultRoute: /app/security/overview

# Default index pattern
defaultIndex: security-*

# Time filter defaults
timepicker:timeDefaults: 
  from: now-24h
  to: now
```

### Step 4: Configure Role-Based Access to Spaces

```bash
POST /_security/role/soc_analyst
{
  "cluster": ["monitor"],
  "indices": [
    {
      "names": ["security-*", "logs-*", ".siem-signals-*"],
      "privileges": ["read", "write"]
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["feature_siem.all", "feature_dashboard.read"],
      "resources": ["space:security-ops"]
    }
  ]
}
```

### Step 5: Create User and Assign Role

```bash
POST /_security/user/john_analyst
{
  "password": "changeme",
  "roles": ["soc_analyst"],
  "full_name": "John Analyst",
  "email": "john@example.com"
}
```

**Documentation:** https://www.elastic.co/guide/en/kibana/current/spaces-managing.html

## Fleet Configuration

### Step 1: Install Fleet Server

Fleet Server can run on a dedicated host or on an existing Elasticsearch node (not recommended for production).

```bash
# Download Elastic Agent
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.x.x-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.x.x-linux-x86_64.tar.gz
cd elastic-agent-8.x.x-linux-x86_64/

# Install Fleet Server
sudo ./elastic-agent install \
  --fleet-server-es=https://elasticsearch-node1:9200 \
  --fleet-server-service-token=<service-token> \
  --fleet-server-policy=fleet-server-policy \
  --fleet-server-es-ca=/path/to/elasticsearch-ca.crt \
  --fleet-server-cert=/path/to/fleet-server.crt \
  --fleet-server-cert-key=/path/to/fleet-server.key \
  --fleet-server-port=8220
```

### Step 2: Generate Service Token (if needed)

```bash
# On Elasticsearch node
./bin/elasticsearch-service-tokens create elastic/fleet-server fleet-server-token
```

### Step 3: Configure Fleet in Kibana

1. Navigate to **Fleet > Settings**
2. Configure Fleet Server hosts:
   ```
   https://fleet-server-host:8220
   ```
3. Configure Elasticsearch output:
   ```
   https://elasticsearch-node1:9200
   https://elasticsearch-node2:9200
   https://elasticsearch-node3:9200
   ```

### Step 4: Create Agent Policies

1. Navigate to **Fleet > Agent policies**
2. Click **Create agent policy**
3. Configure for security endpoints:

```yaml
name: Security Endpoints Policy
description: Policy for endpoint security monitoring
namespace: security
monitoring:
  enabled: true
  use_output: default
  logs: true
  metrics: true
```

### Step 5: Add Integrations

Add security-related integrations to your policy:
- **Elastic Defend** - Endpoint security and EDR (Linux support)
- **Auditd** - Linux audit framework integration
- **System** - System logs and metrics
- **Network Packet Capture** - Network traffic analysis
- **Osquery Manager** - OS querying capabilities

**Documentation:** https://www.elastic.co/guide/en/fleet/current/fleet-server.html

## Elastic Agent Deployment

### Step 1: Generate Enrollment Token

In Kibana:
1. Navigate to **Fleet > Enrollment tokens**
2. Create a new token for your agent policy
3. Copy the token

### Step 2: Deploy Agent on Ubuntu Endpoints

#### Installation:
```bash
# Download agent
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.x.x-linux-x86_64.tar.gz
tar xzvf elastic-agent-8.x.x-linux-x86_64.tar.gz
cd elastic-agent-8.x.x-linux-x86_64/

# Install and enroll
sudo ./elastic-agent install \
  --url=https://fleet-server-host:8220 \
  --enrollment-token=<enrollment-token> \
  --certificate-authorities=/path/to/ca.crt
```

#### Alternative: Install via DEB package:
```bash
# Download the DEB package
wget https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.x.x-amd64.deb

# Install the package
sudo dpkg -i elastic-agent-8.x.x-amd64.deb

# Enroll the agent
sudo elastic-agent enroll \
  --url=https://fleet-server-host:8220 \
  --enrollment-token=<enrollment-token> \
  --certificate-authorities=/path/to/ca.crt

# Start the agent
sudo systemctl start elastic-agent
sudo systemctl enable elastic-agent
```

#### Additional Ubuntu-specific Configuration:
```bash
# Ensure the agent service starts on boot
sudo systemctl enable elastic-agent

# Check service status
sudo systemctl status elastic-agent

# If needed, configure agent to run as a specific user
sudo chown -R elastic-agent:elastic-agent /opt/Elastic/Agent/
```

### Step 3: Configure Elastic Defend Integration

In the agent policy, configure Elastic Defend settings:

```yaml
name: Elastic Defend
type: endpoint
enabled: true
vars:
  - name: preset
    value: DataCollection  # Options: DataCollection, NGAVDetection, EDRComplete
inputs:
  - type: endpoint
    enabled: true
    streams:
      - data_stream:
          dataset: endpoint.events.process
        vars:
          - name: process
            value: true
      - data_stream:
          dataset: endpoint.events.network
        vars:
          - name: network
            value: true
      - data_stream:
          dataset: endpoint.events.file
        vars:
          - name: file
            value: true
      - data_stream:
          dataset: endpoint.alerts
        vars:
          - name: malware
            value: prevent  # Options: detect, prevent, off
          - name: behavior_protection
            value: prevent
          - name: memory_protection
            value: prevent
```

#### Linux-specific Security Configuration:
```yaml
# Additional Linux security monitoring
- name: auditd
  type: auditd
  enabled: true
  vars:
    - name: socket_type
      value: multicast
    - name: immutable
      value: false

- name: system
  type: system/metrics
  enabled: true
  dataset:
    - system.process
    - system.socket
    - system.filesystem
```

### Step 4: Verify Agent Status

#### On the Agent Host:
```bash
# Check agent status
sudo elastic-agent status

# View agent logs
sudo elastic-agent logs
```

#### In Kibana:
1. Navigate to **Fleet > Agents**
2. Verify agents show as "Healthy"
3. Check "Last activity" timestamps

### Step 5: Validate Data Ingestion

```bash
# Check for security data streams
GET /_data_stream/logs-endpoint.events.*

# Verify document count
GET /logs-endpoint.events.*/_count

# Sample query for recent events
GET /logs-endpoint.events.*/_search
{
  "size": 10,
  "sort": [{"@timestamp": "desc"}]
}
```

**Documentation:** https://www.elastic.co/guide/en/fleet/current/elastic-agent-installation.html

## Post-Installation Verification

### Cluster Health Check
```bash
# Check cluster status
curl -X GET "https://localhost:9200/_cluster/health?pretty" \
  -u elastic:password \
  --cacert /path/to/ca.crt

# Verify all nodes are connected
curl -X GET "https://localhost:9200/_cat/nodes?v" \
  -u elastic:password \
  --cacert /path/to/ca.crt
```

### Security Verification
```bash
# Verify security is enabled
GET /_xpack/security

# Check license status
GET /_license

# List users
GET /_security/user

# Verify SSL/TLS
openssl s_client -connect localhost:9200 -showcerts
```

### Data Pipeline Verification
```bash
# Check ILM policies
GET /_ilm/policy

# Verify index templates
GET /_index_template

# Check data streams
GET /_data_stream

# Monitor ingest pipelines
GET /_ingest/pipeline
```

## Security Best Practices

### 1. Authentication & Authorization
- Use strong passwords for built-in users
- Create dedicated users with minimal required privileges
- Regularly rotate API keys and passwords
- Enable audit logging for security events

### 2. Network Security
- Bind Elasticsearch to specific network interfaces, not 0.0.0.0
- Use firewall rules to restrict access to Elasticsearch ports
- Implement network segmentation between different environments
- Use VPN or private networks for remote access

### 3. Encryption
- Always enable TLS for both transport and HTTP layers
- Use strong cipher suites
- Regularly update certificates before expiration
- Store certificate passwords in the secure keystore

### 4. Monitoring & Alerting
- Monitor cluster health and performance
- Set up alerts for security events
- Track failed authentication attempts
- Monitor unusual API usage patterns

### 5. Data Protection
- Implement appropriate ILM policies for data retention
- Regular snapshots for backup and recovery
- Enable encryption at rest if required
- Implement field-level and document-level security where needed

## References

### Official Documentation

1. **Installation and Setup**
   - https://www.elastic.co/guide/en/elasticsearch/reference/current/install-elasticsearch.html
   - https://www.elastic.co/guide/en/elasticsearch/reference/current/settings.html

2. **License Management**
   - https://www.elastic.co/guide/en/kibana/current/managing-licenses.html
   - https://www.elastic.co/subscriptions

3. **Security Configuration**
   - https://www.elastic.co/guide/en/elasticsearch/reference/current/security-basic-setup.html
   - https://www.elastic.co/guide/en/elasticsearch/reference/current/security-api.html

4. **Index Management**
   - https://www.elastic.co/guide/en/elasticsearch/reference/current/index-templates.html
   - https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html

5. **Kibana Configuration**
   - https://www.elastic.co/guide/en/kibana/current/data-views.html
   - https://www.elastic.co/guide/en/kibana/current/spaces-managing.html

6. **Fleet and Elastic Agent**
   - https://www.elastic.co/guide/en/fleet/current/fleet-server.html
   - https://www.elastic.co/guide/en/fleet/current/elastic-agent-installation.html

---

*Note: This document provides a comprehensive guide for setting up a self-managed Elastic cluster with Enterprise licensing for security use cases. Always refer to the official Elastic documentation for the most current information and version-specific details.*