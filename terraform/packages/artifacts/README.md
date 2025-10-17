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
