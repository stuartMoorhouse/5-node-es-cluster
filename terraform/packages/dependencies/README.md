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
