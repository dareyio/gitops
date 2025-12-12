#!/bin/bash
set -e

# Build script for BBB images (bbb-web and bbb-html5)
# This script builds BBB images from the BBB Docker repository and pushes them to ECR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BBB_DOCKER_REPO="${BBB_DOCKER_REPO:-/tmp/bbb-docker}"
BBB_VERSION="${BBB_VERSION:-3.0.4}"
ECR_REGISTRY="${ECR_REGISTRY:-586794457112.dkr.ecr.eu-west-2.amazonaws.com}"
ECR_REPOSITORY="${ECR_REPOSITORY:-liveclasses}"
AWS_REGION="${AWS_REGION:-eu-west-2}"

# Image names
BBB_WEB_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}/bbb-web:${BBB_VERSION}"
BBB_HTML5_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}/bbb-html5:${BBB_VERSION}"

echo -e "${GREEN}=== BBB Image Build Script ===${NC}"
echo ""
echo "Configuration:"
echo "  BBB Docker Repo: ${BBB_DOCKER_REPO}"
echo "  BBB Version: ${BBB_VERSION}"
echo "  ECR Registry: ${ECR_REGISTRY}"
echo "  ECR Repository: ${ECR_REPOSITORY}"
echo "  AWS Region: ${AWS_REGION}"
echo ""

# Check if BBB Docker repo exists
if [ ! -d "${BBB_DOCKER_REPO}" ]; then
    echo -e "${RED}Error: BBB Docker repository not found at ${BBB_DOCKER_REPO}${NC}"
    echo "Please clone it first:"
    echo "  git clone --recurse-submodules https://github.com/bigbluebutton/docker.git ${BBB_DOCKER_REPO}"
    exit 1
fi

cd "${BBB_DOCKER_REPO}"

# Check if .env exists, create from sample if not
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env from sample.env...${NC}"
    cp sample.env .env
    echo -e "${YELLOW}Please review and update .env file with your settings${NC}"
    echo "  - Set BBB_BUILD_TAG=${BBB_VERSION}"
    echo "  - Set EXTERNAL_IPv4 (required)"
    echo "  - Set DOMAIN (required)"
    exit 1
fi

# Load .env
source .env

# Ensure BBB_BUILD_TAG is set
if [ -z "${BBB_BUILD_TAG}" ]; then
    echo -e "${YELLOW}Setting BBB_BUILD_TAG=${BBB_VERSION} in .env${NC}"
    echo "BBB_BUILD_TAG=${BBB_VERSION}" >> .env
    export BBB_BUILD_TAG="${BBB_VERSION}"
fi

# Check if submodules are initialized
echo -e "${GREEN}Checking Git submodules...${NC}"
if [ ! -d "repos/bigbluebutton" ] || [ ! -d "repos/freeswitch" ]; then
    echo -e "${YELLOW}Initializing Git submodules...${NC}"
    git submodule update --init --recursive || {
        echo -e "${RED}Failed to initialize submodules. This may be due to network issues.${NC}"
        echo "Please retry when network is stable, or clone manually:"
        echo "  cd ${BBB_DOCKER_REPO}"
        echo "  git submodule update --init --recursive"
        exit 1
    }
fi

# Generate docker-compose.yml
echo -e "${GREEN}Generating docker-compose.yml...${NC}"
./scripts/generate-compose || {
    echo -e "${RED}Failed to generate docker-compose.yml${NC}"
    exit 1
}

# Login to ECR
echo -e "${GREEN}Logging in to ECR...${NC}"
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}" || {
    echo -e "${RED}Failed to login to ECR${NC}"
    echo "Ensure AWS credentials are configured (aws configure)"
    exit 1
}

# Build base-java image first (required for bbb-web)
echo -e "${GREEN}Building base-java image...${NC}"
docker build -t alangecker/bbb-docker-base-java:latest mod/base-java || {
    echo -e "${RED}Failed to build base-java image${NC}"
    exit 1
}

# Build bbb-web image
echo -e "${GREEN}Building bbb-web image...${NC}"
echo "This may take 10-20 minutes..."
docker compose build bbb-web || {
    echo -e "${RED}Failed to build bbb-web image${NC}"
    exit 1
}

# Tag bbb-web image for ECR
BBB_WEB_LOCAL_IMAGE=$(docker compose images -q bbb-web 2>/dev/null || echo "")
if [ -z "${BBB_WEB_LOCAL_IMAGE}" ]; then
    # Try to find the image by name
    BBB_WEB_LOCAL_IMAGE=$(docker images --format "{{.ID}}" alangecker/bbb-docker-web:* | head -1)
fi

if [ -z "${BBB_WEB_LOCAL_IMAGE}" ]; then
    echo -e "${RED}Could not find built bbb-web image${NC}"
    echo "Available images:"
    docker images | grep -E "bbb|alangecker" | head -10
    exit 1
fi

echo -e "${GREEN}Tagging bbb-web image...${NC}"
docker tag "${BBB_WEB_LOCAL_IMAGE}" "${BBB_WEB_IMAGE}"

# Build bbb-html5 image (from nginx service which serves HTML5)
echo -e "${GREEN}Building nginx image (serves HTML5)...${NC}"
docker compose build nginx || {
    echo -e "${RED}Failed to build nginx image${NC}"
    exit 1
}

# Tag nginx image as bbb-html5 for ECR
NGINX_LOCAL_IMAGE=$(docker compose images -q nginx 2>/dev/null || echo "")
if [ -z "${NGINX_LOCAL_IMAGE}" ]; then
    NGINX_LOCAL_IMAGE=$(docker images --format "{{.ID}}" alangecker/bbb-docker-nginx:* | head -1)
fi

if [ -z "${NGINX_LOCAL_IMAGE}" ]; then
    echo -e "${RED}Could not find built nginx image${NC}"
    exit 1
fi

echo -e "${GREEN}Tagging nginx image as bbb-html5...${NC}"
docker tag "${NGINX_LOCAL_IMAGE}" "${BBB_HTML5_IMAGE}"

# Push images to ECR
echo -e "${GREEN}Pushing images to ECR...${NC}"
echo "Pushing ${BBB_WEB_IMAGE}..."
docker push "${BBB_WEB_IMAGE}" || {
    echo -e "${RED}Failed to push bbb-web image${NC}"
    exit 1
}

echo "Pushing ${BBB_HTML5_IMAGE}..."
docker push "${BBB_HTML5_IMAGE}" || {
    echo -e "${RED}Failed to push bbb-html5 image${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}=== Build Complete! ===${NC}"
echo ""
echo "Images pushed to ECR:"
echo "  - ${BBB_WEB_IMAGE}"
echo "  - ${BBB_HTML5_IMAGE}"
echo ""
echo "You can now update your Kubernetes deployments to use these images."

