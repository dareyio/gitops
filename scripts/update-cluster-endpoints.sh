#!/bin/bash
# Script to update ArgoCD application destination.server endpoints after clusters are created
# Usage: ./update-cluster-endpoints.sh <workload-endpoint> [ops-endpoint]

set -e

WORKLOAD_ENDPOINT=${1:-""}
OPS_ENDPOINT=${2:-""}

if [ -z "$WORKLOAD_ENDPOINT" ]; then
  echo "Usage: $0 <workload-endpoint> [ops-endpoint]"
  echo "Example: $0 https://abc123.xyz.eks.eu-west-2.amazonaws.com [https://def456.xyz.eks.eu-west-2.amazonaws.com]"
  exit 1
fi

# Update prod-workload applications
echo "Updating prod-workload cluster endpoints..."
find argocd/applications/prod-workload/applications -name "*.yaml" -type f -exec sed -i.bak "s|server: https://kubernetes.default.svc|server: ${WORKLOAD_ENDPOINT}|g" {} \;

# Update prod-ops applications (if endpoint provided)
if [ -n "$OPS_ENDPOINT" ]; then
  echo "Updating prod-ops cluster endpoints..."
  find argocd/applications/prod-ops/applications -name "*.yaml" -type f -exec sed -i.bak "s|server: https://kubernetes.default.svc|server: ${OPS_ENDPOINT}|g" {} \;
else
  echo "Skipping prod-ops (endpoint not provided)"
fi

# Clean up backup files
find argocd/applications/prod-workload/applications -name "*.bak" -delete
if [ -n "$OPS_ENDPOINT" ]; then
  find argocd/applications/prod-ops/applications -name "*.bak" -delete
fi

echo ""
echo "✅ Updated all application endpoints"
echo "Workload cluster: ${WORKLOAD_ENDPOINT}"
if [ -n "$OPS_ENDPOINT" ]; then
  echo "Ops cluster: ${OPS_ENDPOINT}"
fi

