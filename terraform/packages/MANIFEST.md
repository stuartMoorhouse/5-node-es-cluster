# Air-Gapped Elastic Stack Package Manifest

**Generated:** Fri Oct 17 17:14:41 CEST 2025
**Elasticsearch Version:** 9.1.5
**Kibana Version:** 9.1.5
**Cribl Stream Version:** 4.8.2
**Java Version:** 17
**EPR Version:** v9.1.5

## Directory Structure

```
packages/
├── elasticsearch/          # Elasticsearch DEB package
│   ├── elasticsearch-9.1.5-amd64.deb
│   └── elasticsearch-9.1.5-amd64.deb.sha512
├── kibana/                 # Kibana DEB package
│   ├── kibana-9.1.5-amd64.deb
│   └── kibana-9.1.5-amd64.deb.sha512
├── cribl/                  # Cribl Stream tarball
│   └── cribl-4.8.2-linux-x64.tgz
├── epr/                    # Elastic Package Registry
│   ├── epr-v9.1.5.tar (Docker image)
│   └── README.md
├── nginx/                  # Nginx for Artifact Registry
│   ├── nginx_*.deb
│   └── README.md
├── artifacts/              # Elastic Agent binaries
│   ├── elastic-agent-*-linux-x86_64.tar.gz
│   └── README.md
├── java/                   # OpenJDK packages
│   ├── openjdk-17-jre-headless_*.deb
│   └── (dependencies)
├── dependencies/           # System dependencies
│   ├── apt-transport-https_*.deb
│   ├── ca-certificates_*.deb
│   └── (other dependencies)
└── MANIFEST.md            # This file
```

## Package Counts

- Elasticsearch:        1 DEB packages
- Kibana:        1 DEB packages
- Cribl:        0 tarballs
- EPR:        0 Docker images
- Nginx:        0 DEB packages
- Java:        0 DEB packages
- Dependencies:        0 DEB packages

**Total DEB packages:**        2
**Total size:** 1.0G

## Verification

To verify package integrity:

```bash
# Elasticsearch
cd /Users/stuart/Documents/code/working/5-node-es-cluster/terraform/scripts/../packages/elasticsearch
sha512sum -c elasticsearch-9.1.5-amd64.deb.sha512

# Kibana
cd /Users/stuart/Documents/code/working/5-node-es-cluster/terraform/scripts/../packages/kibana
sha512sum -c kibana-9.1.5-amd64.deb.sha512
```

## What This Demonstrates

This air-gapped deployment showcases:

1. **Local Package Installation**: Elasticsearch and Kibana installed from local .deb files
2. **Elastic Package Registry (EPR)**: Local registry for integrations instead of epr.elastic.co
3. **Artifact Registry**: Local web server for Elastic Agent binary downloads
4. **Cribl Stream**: Data ingestion and routing without internet access

## Deployment

1. Ensure all packages are present (check above counts)
2. Transfer the entire `packages/` directory to your deployment machine
3. Run Terraform:
   ```bash
   terraform apply -var="deployment_mode=airgapped" -var="data_source_type=cribl"
   ```
4. Terraform will automatically upload packages to droplets and install them

## Post-Deployment

After deployment:
- Kibana will use the local EPR at http://10.10.10.2:8443
- Fleet will download agents from http://10.10.10.3:9080
- All services operate without internet connectivity
