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
