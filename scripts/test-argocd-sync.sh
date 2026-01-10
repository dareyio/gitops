#!/bin/bash

set +e

APP_NAME="lab-controller"
PROD_OPS_CONTEXT="prod-ops"
STAGING_WORKLOAD_CONTEXT="staging-workload"
TEST_LABEL="argocd-test"
TEST_VALUE="2026-01-10-verification"
MAX_WAIT=180
INTERVAL=5
ELAPSED=0

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Testing ArgoCD Sync: $APP_NAME to staging-workload           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "1. Checking initial ArgoCD application status..."
INITIAL_STATUS=$(kubectl get application "$APP_NAME" -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.status}' 2>/dev/null)
INITIAL_REVISION=$(kubectl get application "$APP_NAME" -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.revision}' 2>/dev/null)
echo "   Initial Status: $INITIAL_STATUS"
echo "   Initial Revision: $INITIAL_REVISION"
echo ""

echo "2. Waiting for ArgoCD to detect the change..."
while [ $ELAPSED -lt $MAX_WAIT ]; do
    CURRENT_STATUS=$(kubectl get application "$APP_NAME" -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.status}' 2>/dev/null)
    CURRENT_REVISION=$(kubectl get application "$APP_NAME" -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.revision}' 2>/dev/null)
    
    if [ "$CURRENT_STATUS" != "$INITIAL_STATUS" ] || [ "$CURRENT_REVISION" != "$INITIAL_REVISION" ]; then
        echo "   ✓ Change detected! Status: $CURRENT_STATUS, Revision: $CURRENT_REVISION"
        break
    fi
    
    echo "   [${ELAPSED}s] Waiting... (Status: $CURRENT_STATUS)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "   ⚠ Timeout waiting for ArgoCD to detect change"
    echo "   Current status: $CURRENT_STATUS"
    exit 1
fi

echo ""
echo "3. Waiting for ArgoCD to sync the change..."
SYNC_WAIT=0
SYNC_MAX_WAIT=120

while [ $SYNC_WAIT -lt $SYNC_MAX_WAIT ]; do
    SYNC_STATUS=$(kubectl get application "$APP_NAME" -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.status}' 2>/dev/null)
    HEALTH_STATUS=$(kubectl get application "$APP_NAME" -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.health.status}' 2>/dev/null)
    
    if [ "$SYNC_STATUS" = "Synced" ]; then
        echo "   ✓ Sync complete! Status: $SYNC_STATUS, Health: $HEALTH_STATUS"
        break
    fi
    
    echo "   [${SYNC_WAIT}s] Syncing... (Status: $SYNC_STATUS, Health: $HEALTH_STATUS)"
    sleep $INTERVAL
    SYNC_WAIT=$((SYNC_WAIT + INTERVAL))
done

if [ $SYNC_WAIT -ge $SYNC_MAX_WAIT ]; then
    echo "   ⚠ Timeout waiting for sync to complete"
    echo "   Current status: $SYNC_STATUS"
    exit 1
fi

echo ""
echo "4. Verifying deployment in staging-workload cluster..."
DEPLOYMENT_LABEL=$(kubectl get deployment "$APP_NAME" -n lab-controller --context="$STAGING_WORKLOAD_CONTEXT" -o jsonpath="{.metadata.labels.$TEST_LABEL}" 2>/dev/null)

if [ "$DEPLOYMENT_LABEL" = "$TEST_VALUE" ]; then
    echo "   ✓ SUCCESS! Label '$TEST_LABEL=$TEST_VALUE' found in staging-workload cluster!"
    echo ""
    echo "   Deployment details:"
    kubectl get deployment "$APP_NAME" -n lab-controller --context="$STAGING_WORKLOAD_CONTEXT" -o jsonpath='{.metadata.name}: Replicas: {.spec.replicas}, Ready: {.status.readyReplicas}' && echo ""
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  ✅ VERIFICATION SUCCESSFUL                                   ║"
    echo "║  ArgoCD successfully synced changes to staging-workload!     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    exit 0
else
    echo "   ✗ FAILED! Label not found in staging-workload cluster"
    echo "   Expected: $TEST_LABEL=$TEST_VALUE"
    echo "   Found: $DEPLOYMENT_LABEL"
    echo ""
    echo "   Current labels:"
    kubectl get deployment "$APP_NAME" -n lab-controller --context="$STAGING_WORKLOAD_CONTEXT" -o jsonpath='{.metadata.labels}' | jq '.' 2>/dev/null || kubectl get deployment "$APP_NAME" -n lab-controller --context="$STAGING_WORKLOAD_CONTEXT" -o jsonpath='{.metadata.labels}'
    exit 1
fi
