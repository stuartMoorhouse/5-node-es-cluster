# Elastic Package Registry (EPR) Download Instructions

EPR is distributed as a Docker container image.

## Download EPR Container Image

```bash
# Pull the EPR image
docker pull docker.elastic.co/package-registry/distribution:v9.1.5

# Save the image to a tar file
docker save docker.elastic.co/package-registry/distribution:v9.1.5 -o /Users/stuart/Documents/code/working/5-node-es-cluster/terraform/scripts/../packages/epr/epr-v9.1.5.tar

# Verify the image
ls -lh /Users/stuart/Documents/code/working/5-node-es-cluster/terraform/scripts/../packages/epr/epr-v9.1.5.tar
```

## Load on Air-Gapped System

```bash
# Load the image on the target system
docker load -i epr-v9.1.5.tar

# Run EPR
docker run -d -p 8443:8080 docker.elastic.co/package-registry/distribution:v9.1.5
```

## Alternative: Use EPR Binary

Download the standalone binary from:
https://github.com/elastic/package-registry/releases
