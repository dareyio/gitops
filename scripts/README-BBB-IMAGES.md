# BBB Image Build Guide

This guide explains how to build BigBlueButton (BBB) images for the liveclasses deployment.

## Overview

BBB requires two main images:
1. **bbb-web**: The Java/Grails backend API server
2. **bbb-html5**: The HTML5 frontend client (served via Nginx)

## Local Build (Testing)

### Prerequisites

1. **Clone BBB Docker repository:**
   ```bash
   git clone --recurse-submodules https://github.com/bigbluebutton/docker.git /tmp/bbb-docker
   cd /tmp/bbb-docker
   ```

2. **Configure AWS credentials:**
   ```bash
   aws configure
   # Or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
   ```

3. **Set up environment:**
   ```bash
   cd /tmp/bbb-docker
   cp sample.env .env
   # Edit .env and set:
   # - BBB_BUILD_TAG=3.0.4 (or your desired version)
   # - EXTERNAL_IPv4=<your-external-ip>
   # - DOMAIN=<your-domain>
   # - Other required variables
   ```

### Build Script

Use the automated build script:

```bash
cd /Users/dare/Desktop/xterns/darey-new
./scripts/build-bbb-images.sh
```

**Environment Variables:**
- `BBB_DOCKER_REPO`: Path to BBB Docker repo (default: `/tmp/bbb-docker`)
- `BBB_VERSION`: BBB version to build (default: `3.0.4`)
- `ECR_REGISTRY`: ECR registry URL (default: `586794457112.dkr.ecr.eu-west-2.amazonaws.com`)
- `ECR_REPOSITORY`: ECR repository name (default: `liveclasses`)
- `AWS_REGION`: AWS region (default: `eu-west-2`)

**Example:**
```bash
BBB_VERSION=3.0.4 ./scripts/build-bbb-images.sh
```

### Manual Build

If you prefer to build manually:

```bash
cd /tmp/bbb-docker

# 1. Generate docker-compose.yml
./scripts/generate-compose

# 2. Build base-java (required dependency)
docker build -t alangecker/bbb-docker-base-java:latest mod/base-java

# 3. Build bbb-web
docker compose build bbb-web

# 4. Build nginx (serves HTML5)
docker compose build nginx

# 5. Login to ECR
aws ecr get-login-password --region eu-west-2 | \
  docker login --username AWS --password-stdin 586794457112.dkr.ecr.eu-west-2.amazonaws.com

# 6. Tag and push images
docker tag <bbb-web-image-id> 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-web:3.0.4
docker tag <nginx-image-id> 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-html5:3.0.4

docker push 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-web:3.0.4
docker push 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-html5:3.0.4
```

## CI/CD Build (GitHub Actions)

The GitHub Actions workflow automatically builds and pushes images to ECR.

### Triggering the Workflow

**Manual Trigger:**
1. Go to GitHub Actions tab
2. Select "Build and Push BBB Images"
3. Click "Run workflow"
4. Enter BBB version (e.g., `3.0.4`)
5. Choose whether to push to ECR

**Automatic Triggers:**
- Push to `main` branch (if build script or workflow file changes)
- Weekly schedule (Mondays at 2 AM UTC)

### Required Secrets

Ensure these secrets are configured in GitHub:
- `AWS_ACCESS_KEY_ID`: AWS access key with ECR push permissions
- `AWS_SECRET_ACCESS_KEY`: AWS secret key

### Workflow Configuration

The workflow is located at:
```
.github/workflows/build-bbb-images.yml
```

## Image Details

### bbb-web Image
- **Source**: `mod/bbb-web/Dockerfile`
- **Base**: `bigbluebutton/bbb-build:3.0.4` → `alangecker/bbb-docker-base-java`
- **Purpose**: Java/Grails backend API server
- **Port**: 8090
- **Dependencies**: MongoDB, Redis

### bbb-html5 Image
- **Source**: `mod/nginx/Dockerfile` (serves HTML5 client)
- **Base**: Nginx with BBB HTML5 client
- **Purpose**: HTML5 frontend client
- **Port**: 80/443
- **Dependencies**: bbb-web API

## Troubleshooting

### Submodule Clone Fails
**Error**: `fatal: unable to access 'https://github.com/...'`

**Solution**: Retry when network is stable, or clone submodules manually:
```bash
cd /tmp/bbb-docker
git submodule update --init --recursive
```

### Build Fails with "Cannot find module"
**Error**: Build fails due to missing dependencies

**Solution**: Ensure all submodules are initialized:
```bash
cd /tmp/bbb-docker
git submodule update --init --recursive
```

### ECR Push Fails
**Error**: `no basic auth credentials`

**Solution**: Re-authenticate with ECR:
```bash
aws ecr get-login-password --region eu-west-2 | \
  docker login --username AWS --password-stdin 586794457112.dkr.ecr.eu-west-2.amazonaws.com
```

### Build Takes Too Long
**Note**: BBB builds can take 20-40 minutes due to:
- Large codebase compilation
- Multiple dependency builds
- Grails/Gradle builds

This is normal. Consider running in CI/CD for automated builds.

## Verification

After building, verify images are in ECR:

```bash
aws ecr describe-images \
  --repository-name liveclasses \
  --region eu-west-2 \
  --image-ids imageTag=bbb-web:3.0.4

aws ecr describe-images \
  --repository-name liveclasses \
  --region eu-west-2 \
  --image-ids imageTag=bbb-html5:3.0.4
```

## Next Steps

Once images are built and pushed:
1. Kubernetes will automatically pull the new images
2. Pods should start successfully
3. Verify with: `kubectl get pods -n liveclasses`

