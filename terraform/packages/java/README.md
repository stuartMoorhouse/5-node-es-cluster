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
