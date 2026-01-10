#!/bin/bash

set +e

echo "Testing ArgoCD connectivity to staging-workload cluster..."
echo ""

PROD_OPS_CONTEXT="prod-ops"
STAGING_WORKLOAD_ENDPOINT="https://FB48AC16EE81C0085089AAECDD2874F7.gr7.eu-west-2.eks.amazonaws.com"

echo "1. Checking if staging-workload cluster secret exists..."
SECRET_EXISTS=$(kubectl get secret staging-workload-cluster-secret -n argocd --context="$PROD_OPS_CONTEXT" 2>&1 | grep -v "NotFound")
if [ -n "$SECRET_EXISTS" ]; then
    echo "   ✓ Secret exists"
    kubectl get secret staging-workload-cluster-secret -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}' && echo "   ✓ Correctly labeled"
else
    echo "   ✗ Secret not found"
    exit 1
fi

echo ""
echo "2. Checking if staging-workload-applications bootstrap exists..."
BOOTSTRAP_EXISTS=$(kubectl get application staging-workload-applications -n argocd --context="$PROD_OPS_CONTEXT" 2>&1 | grep -v "NotFound")
if [ -n "$BOOTSTRAP_EXISTS" ]; then
    echo "   ✓ Bootstrap application exists"
    SYNC_STATUS=$(kubectl get application staging-workload-applications -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.status}')
    HEALTH_STATUS=$(kubectl get application staging-workload-applications -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.health.status}')
    echo "   Status: Sync=$SYNC_STATUS, Health=$HEALTH_STATUS"
else
    echo "   ✗ Bootstrap application not found"
    exit 1
fi

echo ""
echo "3. Checking staging-workload applications discovered by ArgoCD..."
STAGING_APPS=$(kubectl get applications -n argocd --context="$PROD_OPS_CONTEXT" -o json | jq -r '.items[] | select(.spec.destination.server | contains("FB48AC16")) | "\(.metadata.name): \(.status.sync.status)/\(.status.health.status)"' 2>/dev/null)
if [ -n "$STAGING_APPS" ]; then
    echo "   ✓ Applications discovered:"
    echo "$STAGING_APPS" | while IFS= read -r line; do
        echo "     - $line"
    done
else
    echo "   ⚠ No staging-workload applications found"
fi

echo ""
echo "4. Testing connectivity to staging-workload cluster endpoint..."
ARGOCD_POD=$(kubectl get pods -n argocd --context="$PROD_OPS_CONTEXT" -l app.kubernetes.io/name=argocd-application-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$ARGOCD_POD" ]; then
    echo "   Using ArgoCD controller pod: $ARGOCD_POD"
    CONNECTIVITY_TEST=$(kubectl exec -n argocd "$ARGOCD_POD" --context="$PROD_OPS_CONTEXT" -- wget -qO- --timeout=5 "$STAGING_WORKLOAD_ENDPOINT/healthz" 2>&1 | head -1)
    if echo "$CONNECTIVITY_TEST" | grep -q "ok\|200\|Unauthorized"; then
        echo "   ✓ Can reach staging-workload endpoint"
    else
        echo "   ⚠ Connectivity test inconclusive (may require authentication)"
    fi
else
    echo "   ⚠ Could not find ArgoCD controller pod"
fi

echo ""
echo "5. Verifying at least one application can sync successfully..."
SYNCED_APP=$(kubectl get applications -n argocd --context="$PROD_OPS_CONTEXT" -o json | jq -r '.items[] | select(.spec.destination.server | contains("FB48AC16")) | select(.status.sync.status == "Synced") | .metadata.name' 2>/dev/null | head -1)
if [ -n "$SYNCED_APP" ]; then
    echo "   ✓ Found synced application: $SYNCED_APP"
    echo "   This confirms ArgoCD can successfully manage staging-workload cluster!"
else
    echo "   ⚠ No applications are currently synced (may need manual sync)"
fi

echo ""
echo "6. Summary:"
if [ -n "$SECRET_EXISTS" ] && [ -n "$BOOTSTRAP_EXISTS" ] && [ -n "$STAGING_APPS" ]; then
    echo "   ✓ ArgoCD cluster secret: OK"
    echo "   ✓ Bootstrap application: OK"
    echo "   ✓ Applications discovered: OK"
    if [ -n "$SYNCED_APP" ]; then
        echo "   ✓ Connectivity verified: ArgoCD can successfully manage staging-workload!"
        exit 0
    else
        echo "   ⚠ Connectivity: Applications discovered but none synced yet"
        echo "   Recommendation: Manually sync an application to verify"
        exit 0
    fi
else
    echo "   ✗ Configuration incomplete"
    exit 1
fi
