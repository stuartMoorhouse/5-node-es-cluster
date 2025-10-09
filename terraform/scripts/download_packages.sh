#!/bin/bash
set -euo pipefail

# Elasticsearch Air-Gapped Package Download Script
# This script downloads all required packages for air-gapped Elasticsearch deployment
# Run this on an internet-connected machine before deploying to air-gapped environment

# Configuration
ES_VERSION="9.1.5"
JAVA_VERSION="17"
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
    mkdir -p "${PACKAGES_DIR}"/{elasticsearch,java,dependencies}
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
# Air-Gapped Elasticsearch Package Manifest

**Generated:** $(date)
**Elasticsearch Version:** ${ES_VERSION}
**Java Version:** ${JAVA_VERSION}

## Directory Structure

\`\`\`
packages/
├── elasticsearch/          # Elasticsearch DEB package
│   ├── elasticsearch-${ES_VERSION}-amd64.deb
│   └── elasticsearch-${ES_VERSION}-amd64.deb.sha512
├── java/                   # OpenJDK packages
│   ├── openjdk-17-jre-headless_*.deb
│   └── (dependencies)
├── dependencies/           # System dependencies
│   ├── apt-transport-https_*.deb
│   ├── ca-certificates_*.deb
│   ├── curl_*.deb
│   ├── jq_*.deb
│   └── (other dependencies)
└── MANIFEST.md            # This file
\`\`\`

## Package Counts

- Elasticsearch packages: $(find "${PACKAGES_DIR}/elasticsearch" -name "*.deb" 2>/dev/null | wc -l)
- Java packages: $(find "${PACKAGES_DIR}/java" -name "*.deb" 2>/dev/null | wc -l)
- System dependencies: $(find "${PACKAGES_DIR}/dependencies" -name "*.deb" 2>/dev/null | wc -l)

**Total DEB packages:** $(find "${PACKAGES_DIR}" -name "*.deb" 2>/dev/null | wc -l)
**Total size:** $(du -sh "${PACKAGES_DIR}" | cut -f1)

## Verification

To verify Elasticsearch package integrity:

\`\`\`bash
cd ${PACKAGES_DIR}/elasticsearch
sha512sum -c elasticsearch-${ES_VERSION}-amd64.deb.sha512
\`\`\`

## Next Steps

1. Review the downloaded packages
2. Transfer the entire \`packages/\` directory to your deployment machine
3. Run \`terraform apply\` to deploy the air-gapped cluster
4. Terraform will automatically upload these packages to droplets
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
    log_info "Elasticsearch Air-Gapped Package Downloader"
    log_info "Version: ${ES_VERSION}"
    log_info "========================================="
    echo

    create_directories
    download_elasticsearch
    download_java
    download_dependencies
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
    log_info "2. Check ${PACKAGES_DIR}/java/README.md for Java packages"
    log_info "3. Check ${PACKAGES_DIR}/dependencies/README.md for system packages"
    log_info "4. Ensure all packages are downloaded before deployment"
    log_info "5. Run 'terraform apply' to deploy air-gapped cluster"
    echo
}

# Run main function
main "$@"
