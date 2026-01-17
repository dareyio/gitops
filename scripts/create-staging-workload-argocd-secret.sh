#!/bin/bash

set -e

echo "Creating ArgoCD cluster secret for staging-workload..."

STAGING_WORKLOAD_CONTEXT="staging-workload"
PROD_OPS_CONTEXT="prod-ops"
SECRET_NAME="staging-workload-cluster-secret"

if ! kubectl config get-contexts | grep -q "$STAGING_WORKLOAD_CONTEXT"; then
    echo "Error: staging-workload context not found in kubeconfig"
    echo "Please configure kubeconfig with staging-workload cluster first"
    exit 1
fi

if ! kubectl config get-contexts | grep -q "$PROD_OPS_CONTEXT"; then
    echo "Error: prod-ops context not found in kubeconfig"
    exit 1
fi

echo "Getting staging-workload cluster credentials..."

CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$STAGING_WORKLOAD_CONTEXT\")].context.cluster}" 2>/dev/null)
ENDPOINT=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.server}" 2>/dev/null | sed 's|https://||')
CA_CERT=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority-data}" 2>/dev/null)

if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: Unable to find cluster name for context $STAGING_WORKLOAD_CONTEXT"
    echo "Available contexts:"
    kubectl config get-contexts
    exit 1
fi

if [ -z "$ENDPOINT" ] || [ -z "$CA_CERT" ]; then
    echo "Error: Unable to get cluster endpoint or CA cert from kubeconfig"
    exit 1
fi

echo "Creating ServiceAccount for ArgoCD in staging-workload cluster..."
kubectl apply -f - --context="$STAGING_WORKLOAD_CONTEXT" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: kube-system
EOF

echo "Waiting for ServiceAccount token..."
sleep 5

TOKEN_SECRET=$(kubectl get sa argocd-manager -n kube-system --context="$STAGING_WORKLOAD_CONTEXT" -o jsonpath='{.secrets[0].name}' 2>/dev/null)
if [ -z "$TOKEN_SECRET" ]; then
    echo "Creating token secret for ServiceAccount..."
    kubectl apply -f - --context="$STAGING_WORKLOAD_CONTEXT" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF
    sleep 5
    TOKEN_SECRET="argocd-manager-token"
fi

BEARER_TOKEN=$(kubectl get secret "$TOKEN_SECRET" -n kube-system --context="$STAGING_WORKLOAD_CONTEXT" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)

if [ -z "$BEARER_TOKEN" ]; then
    echo "Error: Unable to get bearer token"
    exit 1
fi

echo "Creating ArgoCD cluster secret in prod-ops..."
kubectl create secret generic "$SECRET_NAME" \
    --from-literal=name=staging-workload \
    --from-literal=server="https://${ENDPOINT}" \
    --from-literal=config="{\"bearerToken\":\"${BEARER_TOKEN}\",\"tlsClientConfig\":{\"caData\":\"${CA_CERT}\",\"insecure\":false}}" \
    --type=Opaque \
    -n argocd \
    --context="$PROD_OPS_CONTEXT" \
    --dry-run=client -o yaml | kubectl apply -f - --context="$PROD_OPS_CONTEXT"

kubectl label secret "$SECRET_NAME" -n argocd --context="$PROD_OPS_CONTEXT" \
    argocd.argoproj.io/secret-type=cluster \
    --overwrite

echo ""
echo "✓ ArgoCD cluster secret created successfully!"
echo ""
echo "Verify registration:"
echo "  kubectl get clusters.argoproj.io -n argocd --context=$PROD_OPS_CONTEXT"
echo ""
echo "Or use ArgoCD CLI:"
echo "  argocd cluster list"
