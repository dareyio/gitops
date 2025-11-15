#!/bin/bash
# Script to update ArgoCD application destination.server endpoints after clusters are created
# Usage: ./update-cluster-endpoints.sh <blue-endpoint> [green-endpoint]

set -e

BLUE_ENDPOINT=${1:-""}
GREEN_ENDPOINT=${2:-""}

if [ -z "$BLUE_ENDPOINT" ]; then
  echo "Usage: $0 <blue-endpoint> [green-endpoint]"
  echo "Example: $0 https://abc123.xyz.eks.eu-west-2.amazonaws.com [https://def456.xyz.eks.eu-west-2.amazonaws.com]"
  exit 1
fi

# Update prod-blue applications
echo "Updating prod-blue cluster endpoints..."
find argocd/applications/prod-blue/applications -name "*.yaml" -type f -exec sed -i.bak "s|server: https://kubernetes.default.svc|server: ${BLUE_ENDPOINT}|g" {} \;

# Update prod-green applications (if endpoint provided)
if [ -n "$GREEN_ENDPOINT" ]; then
  echo "Updating prod-green cluster endpoints..."
  find argocd/applications/prod-green/applications -name "*.yaml" -type f -exec sed -i.bak "s|server: https://kubernetes.default.svc|server: ${GREEN_ENDPOINT}|g" {} \;
else
  echo "Skipping prod-green (endpoint not provided)"
fi

# Clean up backup files
find argocd/applications/prod-blue/applications -name "*.bak" -delete
if [ -n "$GREEN_ENDPOINT" ]; then
  find argocd/applications/prod-green/applications -name "*.bak" -delete
fi

echo ""
echo "✅ Updated all application endpoints"
echo "Blue cluster: ${BLUE_ENDPOINT}"
if [ -n "$GREEN_ENDPOINT" ]; then
  echo "Green cluster: ${GREEN_ENDPOINT}"
fi

