#!/bin/bash
set -euo pipefail

# Elasticsearch Air-Gapped Package Download Script
# This script downloads all required packages for air-gapped Elasticsearch deployment
# Run this on an internet-connected machine before deploying to air-gapped environment

# Configuration
ES_VERSION="9.1.5"
KIBANA_VERSION="9.1.5"
CRIBL_VERSION="4.8.2"
JAVA_VERSION="17"
EPR_VERSION="v9.1.5"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="${SCRIPT_DIR}/../packages"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create directory structure
create_directories() {
    log_info "Creating package directory structure..."
    mkdir -p "${PACKAGES_DIR}"/{elasticsearch,kibana,java,dependencies,cribl,epr,nginx,artifacts}
}

# Download Elasticsearch DEB package
download_elasticsearch() {
    log_info "Downloading Elasticsearch ${ES_VERSION}..."

    local ES_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ES_VERSION}-amd64.deb"
    local ES_SHA_URL="${ES_URL}.sha512"
    local ES_FILE="${PACKAGES_DIR}/elasticsearch/elasticsearch-${ES_VERSION}-amd64.deb"
    local ES_SHA_FILE="${ES_FILE}.sha512"

    # Download DEB package
    if [ -f "${ES_FILE}" ]; then
        log_warn "Elasticsearch package already exists, skipping download"
    else
        curl -fsSL "${ES_URL}" -o "${ES_FILE}"
        log_info "Downloaded Elasticsearch to ${ES_FILE}"
    fi

    # Download SHA512 checksum
    if [ -f "${ES_SHA_FILE}" ]; then
        log_warn "Elasticsearch SHA512 already exists, skipping download"
    else
        curl -fsSL "${ES_SHA_URL}" -o "${ES_SHA_FILE}"
        log_info "Downloaded SHA512 checksum"
    fi

    # Verify checksum
    log_info "Verifying Elasticsearch package checksum..."
    cd "${PACKAGES_DIR}/elasticsearch"
    if sha512sum -c "elasticsearch-${ES_VERSION}-amd64.deb.sha512" 2>/dev/null; then
        log_info "✓ Checksum verification passed"
    else
        log_error "✗ Checksum verification failed!"
        exit 1
    fi
    cd - > /dev/null
}

# Download Java JRE
download_java() {
    log_info "Downloading OpenJDK ${JAVA_VERSION} JRE..."

    # For Ubuntu 22.04 (which DigitalOcean likely uses)
    local UBUNTU_VERSION="22.04"
    local JAVA_PACKAGE="openjdk-${JAVA_VERSION}-jre-headless"
    local JAVA_FILE="${PACKAGES_DIR}/java/${JAVA_PACKAGE}.deb"

    log_warn "Java package download requires apt-cache or manual download"
    log_info "Creating download instructions file..."

    cat > "${PACKAGES_DIR}/java/README.md" << 'EOF'
# Java Package Download Instructions

The Java JRE package needs to be downloaded based on your Ubuntu version.

## Option 1: Using apt-cache on Ubuntu 22.04 system

```bash
# On an Ubuntu 22.04 machine
apt-get update
cd $(pwd)/java
apt-get download openjdk-17-jre-headless
apt-get download openjdk-17-jre
apt-get download openjdk-17-jdk-headless
apt-cache depends openjdk-17-jre-headless | grep Depends | cut -d: -f2 | xargs apt-get download
```

## Option 2: Using Docker

```bash
cd $(pwd)/java
docker run --rm -v $(pwd):/output ubuntu:22.04 bash -c "
    apt-get update && \
    cd /output && \
    apt-get download openjdk-17-jre-headless && \
    apt-cache depends openjdk-17-jre-headless | grep Depends | cut -d: -f2 | xargs apt-get download
"
```

## Required Packages
- openjdk-17-jre-headless (main package)
- All dependencies listed by apt-cache depends
EOF

    log_info "Created Java download instructions at ${PACKAGES_DIR}/java/README.md"
}

# Download system dependencies
download_dependencies() {
    log_info "Downloading system dependencies..."

    log_warn "System dependencies require apt-cache or manual download"
    log_info "Creating download instructions file..."

    cat > "${PACKAGES_DIR}/dependencies/README.md" << 'EOF'
# System Dependencies Download Instructions

Required packages for Elasticsearch installation:
- apt-transport-https
- ca-certificates
- curl
- software-properties-common
- jq
- gnupg

## Using apt-cache on Ubuntu 22.04 system

```bash
# On an Ubuntu 22.04 machine
apt-get update
cd $(pwd)/dependencies
apt-get download apt-transport-https ca-certificates curl software-properties-common jq gnupg
# Download all dependencies
for pkg in apt-transport-https ca-certificates curl software-properties-common jq gnupg; do
    apt-cache depends $pkg | grep Depends | cut -d: -f2 | xargs apt-get download || true
done
```

## Using Docker

```bash
cd $(pwd)/dependencies
docker run --rm -v $(pwd):/output ubuntu:22.04 bash -c "
    apt-get update && \
    cd /output && \
    apt-get download apt-transport-https ca-certificates curl software-properties-common jq gnupg && \
    for pkg in apt-transport-https ca-certificates curl software-properties-common jq gnupg; do
        apt-cache depends \$pkg | grep Depends | cut -d: -f2 | xargs apt-get download || true
    done
"
```
EOF

    log_info "Created dependencies download instructions at ${PACKAGES_DIR}/dependencies/README.md"
}

# Download Kibana DEB package
download_kibana() {
    log_info "Downloading Kibana ${KIBANA_VERSION}..."

    local KIBANA_URL="https://artifacts.elastic.co/downloads/kibana/kibana-${KIBANA_VERSION}-amd64.deb"
    local KIBANA_SHA_URL="${KIBANA_URL}.sha512"
    local KIBANA_FILE="${PACKAGES_DIR}/kibana/kibana-${KIBANA_VERSION}-amd64.deb"
    local KIBANA_SHA_FILE="${KIBANA_FILE}.sha512"

    # Download DEB package
    if [ -f "${KIBANA_FILE}" ]; then
        log_warn "Kibana package already exists, skipping download"
    else
        curl -fsSL "${KIBANA_URL}" -o "${KIBANA_FILE}"
        log_info "Downloaded Kibana to ${KIBANA_FILE}"
    fi

    # Download SHA512 checksum
    if [ -f "${KIBANA_SHA_FILE}" ]; then
        log_warn "Kibana SHA512 already exists, skipping download"
    else
        curl -fsSL "${KIBANA_SHA_URL}" -o "${KIBANA_SHA_FILE}"
        log_info "Downloaded SHA512 checksum"
    fi

    # Verify checksum
    log_info "Verifying Kibana package checksum..."
    cd "${PACKAGES_DIR}/kibana"
    if sha512sum -c "kibana-${KIBANA_VERSION}-amd64.deb.sha512" 2>/dev/null; then
        log_info "✓ Checksum verification passed"
    else
        log_error "✗ Checksum verification failed!"
        exit 1
    fi
    cd - > /dev/null
}

# Download Cribl Stream
download_cribl() {
    log_info "Downloading Cribl Stream ${CRIBL_VERSION}..."

    local CRIBL_URL="https://cdn.cribl.io/dl/${CRIBL_VERSION}/cribl-${CRIBL_VERSION}-linux-x64.tgz"
    local CRIBL_FILE="${PACKAGES_DIR}/cribl/cribl-${CRIBL_VERSION}-linux-x64.tgz"

    if [ -f "${CRIBL_FILE}" ]; then
        log_warn "Cribl Stream package already exists, skipping download"
    else
        if curl -fsSL "${CRIBL_URL}" -o "${CRIBL_FILE}" 2>/dev/null; then
            log_info "Downloaded Cribl Stream to ${CRIBL_FILE}"
        else
            log_warn "Failed to download Cribl Stream ${CRIBL_VERSION}"
            log_warn "Please download manually from https://cribl.io/download/"
            cat > "${PACKAGES_DIR}/cribl/README.md" << 'EOF'
# Cribl Stream Manual Download

Cribl Stream version 4.8.2 is not available via direct download.

## Download Instructions

1. Visit https://cribl.io/download/
2. Select "Cribl Stream" and "Standalone X64"
3. Download the Linux x64 tarball
4. Save as: cribl-<version>-linux-x64.tgz in this directory

## Alternative: Use Docker

```bash
docker pull cribl/cribl:latest
```
EOF
        fi
    fi
}

# Download EPR container image
download_epr() {
    log_info "Setting up EPR (Elastic Package Registry)..."

    cat > "${PACKAGES_DIR}/epr/README.md" << EOF
# Elastic Package Registry (EPR) Download Instructions

EPR is distributed as a Docker container image.

## Download EPR Container Image

\`\`\`bash
# Pull the EPR image
docker pull docker.elastic.co/package-registry/distribution:${EPR_VERSION}

# Save the image to a tar file
docker save docker.elastic.co/package-registry/distribution:${EPR_VERSION} -o ${PACKAGES_DIR}/epr/epr-${EPR_VERSION}.tar

# Verify the image
ls -lh ${PACKAGES_DIR}/epr/epr-${EPR_VERSION}.tar
\`\`\`

## Load on Air-Gapped System

\`\`\`bash
# Load the image on the target system
docker load -i epr-${EPR_VERSION}.tar

# Run EPR
docker run -d -p 8443:8080 docker.elastic.co/package-registry/distribution:${EPR_VERSION}
\`\`\`

## Alternative: Use EPR Binary

Download the standalone binary from:
https://github.com/elastic/package-registry/releases
EOF

    log_info "Created EPR instructions at ${PACKAGES_DIR}/epr/README.md"

    # Try to download EPR container if Docker is available
    if command -v docker &> /dev/null; then
        log_info "Docker found, attempting to download EPR image..."
        if docker pull docker.elastic.co/package-registry/distribution:${EPR_VERSION} 2>/dev/null; then
            docker save docker.elastic.co/package-registry/distribution:${EPR_VERSION} -o "${PACKAGES_DIR}/epr/epr-${EPR_VERSION}.tar"
            log_info "✓ EPR image saved to ${PACKAGES_DIR}/epr/epr-${EPR_VERSION}.tar"
        else
            log_warn "Failed to download EPR image. See README for manual instructions."
        fi
    else
        log_warn "Docker not available. See ${PACKAGES_DIR}/epr/README.md for manual download."
    fi
}

# Download nginx and artifact registry packages
download_artifact_registry() {
    log_info "Setting up Artifact Registry packages..."

    cat > "${PACKAGES_DIR}/nginx/README.md" << 'EOF'
# Nginx Package Download Instructions

Nginx is required for the Artifact Registry server.

## Using apt-cache on Ubuntu 22.04 system

\`\`\`bash
apt-get update
cd $(pwd)
apt-get download nginx nginx-common nginx-core libnginx-mod-http-geoip2
\`\`\`

## Using Docker

\`\`\`bash
cd $(pwd)
docker run --rm -v $(pwd):/output ubuntu:22.04 bash -c "
    apt-get update && \
    cd /output && \
    apt-get download nginx nginx-common nginx-core
"
\`\`\`
EOF

    cat > "${PACKAGES_DIR}/artifacts/README.md" << 'EOF'
# Elastic Agent Artifacts

Place Elastic Agent binaries here for the Artifact Registry to serve.

## Download Agent Binaries

\`\`\`bash
# Download Elastic Agent for different platforms
VERSION="9.2.0"

# Linux x86_64
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-linux-x86_64.tar.gz

# Linux ARM64
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-linux-arm64.tar.gz

# Windows
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-windows-x86_64.zip

# macOS
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-darwin-x86_64.tar.gz
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-darwin-aarch64.tar.gz
\`\`\`

Place all downloaded files in this directory.
EOF

    log_info "Created Artifact Registry instructions"

    # Try to download nginx with Docker
    if command -v docker &> /dev/null; then
        log_info "Downloading nginx packages with Docker..."
        docker run --rm -v "${PACKAGES_DIR}/nginx:/output" ubuntu:22.04 bash -c "
            apt-get update -qq && \
            cd /output && \
            apt-get download -qq nginx nginx-common nginx-core 2>/dev/null
        " && log_info "✓ Nginx packages downloaded" || log_warn "Nginx download failed. See README for manual instructions."
    else
        log_warn "Docker not available. See ${PACKAGES_DIR}/nginx/README.md for manual download."
    fi
}

# Download using Docker method (recommended)
download_with_docker() {
    log_info "Attempting to download Java and dependencies using Docker..."

    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found. Please download Java and dependencies manually."
        return 1
    fi

    log_info "Downloading Java packages..."
    docker run --rm -v "${PACKAGES_DIR}/java:/output" ubuntu:22.04 bash -c "
        apt-get update -qq && \
        cd /output && \
        apt-get download -qq openjdk-17-jre-headless openjdk-17-jre 2>/dev/null && \
        apt-cache depends openjdk-17-jre-headless | grep 'Depends:' | cut -d: -f2 | tr -d ' ' | xargs apt-get download -qq 2>/dev/null || true
    " && log_info "✓ Java packages downloaded" || log_warn "Java download partially completed"

    log_info "Downloading system dependencies..."
    docker run --rm -v "${PACKAGES_DIR}/dependencies:/output" ubuntu:22.04 bash -c "
        apt-get update -qq && \
        cd /output && \
        apt-get download -qq apt-transport-https ca-certificates curl software-properties-common jq gnupg 2>/dev/null && \
        for pkg in apt-transport-https ca-certificates curl software-properties-common jq gnupg; do
            apt-cache depends \$pkg | grep 'Depends:' | cut -d: -f2 | tr -d ' ' | xargs apt-get download -qq 2>/dev/null || true
        done
    " && log_info "✓ Dependencies downloaded" || log_warn "Dependencies download partially completed"
}

# Create manifest file
create_manifest() {
    log_info "Creating package manifest..."

    cat > "${PACKAGES_DIR}/MANIFEST.md" << EOF
# Air-Gapped Elastic Stack Package Manifest

**Generated:** $(date)
**Elasticsearch Version:** ${ES_VERSION}
**Kibana Version:** ${KIBANA_VERSION}
**Cribl Stream Version:** ${CRIBL_VERSION}
**Java Version:** ${JAVA_VERSION}
**EPR Version:** ${EPR_VERSION}

## Directory Structure

\`\`\`
packages/
├── elasticsearch/          # Elasticsearch DEB package
│   ├── elasticsearch-${ES_VERSION}-amd64.deb
│   └── elasticsearch-${ES_VERSION}-amd64.deb.sha512
├── kibana/                 # Kibana DEB package
│   ├── kibana-${KIBANA_VERSION}-amd64.deb
│   └── kibana-${KIBANA_VERSION}-amd64.deb.sha512
├── cribl/                  # Cribl Stream tarball
│   └── cribl-${CRIBL_VERSION}-linux-x64.tgz
├── epr/                    # Elastic Package Registry
│   ├── epr-${EPR_VERSION}.tar (Docker image)
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
\`\`\`

## Package Counts

- Elasticsearch: $(find "${PACKAGES_DIR}/elasticsearch" -name "*.deb" 2>/dev/null | wc -l) DEB packages
- Kibana: $(find "${PACKAGES_DIR}/kibana" -name "*.deb" 2>/dev/null | wc -l) DEB packages
- Cribl: $(find "${PACKAGES_DIR}/cribl" -name "*.tgz" 2>/dev/null | wc -l) tarballs
- EPR: $(find "${PACKAGES_DIR}/epr" -name "*.tar" 2>/dev/null | wc -l) Docker images
- Nginx: $(find "${PACKAGES_DIR}/nginx" -name "*.deb" 2>/dev/null | wc -l) DEB packages
- Java: $(find "${PACKAGES_DIR}/java" -name "*.deb" 2>/dev/null | wc -l) DEB packages
- Dependencies: $(find "${PACKAGES_DIR}/dependencies" -name "*.deb" 2>/dev/null | wc -l) DEB packages

**Total DEB packages:** $(find "${PACKAGES_DIR}" -name "*.deb" 2>/dev/null | wc -l)
**Total size:** $(du -sh "${PACKAGES_DIR}" | cut -f1)

## Verification

To verify package integrity:

\`\`\`bash
# Elasticsearch
cd ${PACKAGES_DIR}/elasticsearch
sha512sum -c elasticsearch-${ES_VERSION}-amd64.deb.sha512

# Kibana
cd ${PACKAGES_DIR}/kibana
sha512sum -c kibana-${KIBANA_VERSION}-amd64.deb.sha512
\`\`\`

## What This Demonstrates

This air-gapped deployment showcases:

1. **Local Package Installation**: Elasticsearch and Kibana installed from local .deb files
2. **Elastic Package Registry (EPR)**: Local registry for integrations instead of epr.elastic.co
3. **Artifact Registry**: Local web server for Elastic Agent binary downloads
4. **Cribl Stream**: Data ingestion and routing without internet access

## Deployment

1. Ensure all packages are present (check above counts)
2. Transfer the entire \`packages/\` directory to your deployment machine
3. Run Terraform:
   \`\`\`bash
   terraform apply -var="deployment_mode=airgapped" -var="data_source_type=cribl"
   \`\`\`
4. Terraform will automatically upload packages to droplets and install them

## Post-Deployment

After deployment:
- Kibana will use the local EPR at http://10.10.10.2:8443
- Fleet will download agents from http://10.10.10.3:9080
- All services operate without internet connectivity
EOF

    log_info "Created manifest at ${PACKAGES_DIR}/MANIFEST.md"
}

# Create .gitignore for packages directory
create_gitignore() {
    log_info "Creating .gitignore for packages directory..."

    cat > "${PACKAGES_DIR}/.gitignore" << 'EOF'
# Ignore all DEB packages
*.deb
*.deb.*

# Keep README and manifest files
!README.md
!MANIFEST.md
!.gitignore
EOF

    log_info "Created ${PACKAGES_DIR}/.gitignore"
}

# Main execution
main() {
    log_info "========================================="
    log_info "Elastic Stack Air-Gapped Package Downloader"
    log_info "Elasticsearch: ${ES_VERSION}"
    log_info "Kibana: ${KIBANA_VERSION}"
    log_info "Cribl: ${CRIBL_VERSION}"
    log_info "========================================="
    echo

    create_directories

    # Download core packages
    download_elasticsearch
    download_kibana
    download_cribl
    download_java
    download_dependencies
    echo

    # Download air-gapped infrastructure packages
    download_epr
    download_artifact_registry
    echo

    # Try Docker method if available
    log_info "Attempting automatic download with Docker..."
    if download_with_docker; then
        log_info "Docker-based download completed"
    else
        log_warn "Docker not available or download incomplete"
        log_warn "Please follow manual instructions in README files"
    fi

    echo
    create_gitignore
    create_manifest

    echo
    log_info "========================================="
    log_info "Download process complete!"
    log_info "========================================="
    log_info "Packages location: ${PACKAGES_DIR}"
    log_info ""
    log_info "Next steps:"
    log_info "1. Review ${PACKAGES_DIR}/MANIFEST.md"
    log_info "2. Check ${PACKAGES_DIR}/epr/README.md for EPR setup"
    log_info "3. Check ${PACKAGES_DIR}/nginx/README.md for nginx packages"
    log_info "4. Check ${PACKAGES_DIR}/artifacts/README.md for Elastic Agent binaries"
    log_info "5. Ensure all packages are downloaded before deployment"
    log_info "6. Run 'terraform apply -var=\"deployment_mode=airgapped\"' to deploy"
    echo
}

# Run main function
main "$@"
