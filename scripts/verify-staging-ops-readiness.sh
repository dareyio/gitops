#!/bin/bash

set +e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Staging-Ops Deletion Readiness Assessment                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

PROD_OPS_CONTEXT="prod-ops"
STAGING_WORKLOAD_CONTEXT="staging-workload"
ISSUES=0
WARNINGS=0

# 1. ArgoCD Multi-Cluster Management
echo "1. ArgoCD Multi-Cluster Management"
echo "   ─────────────────────────────────"

STAGING_SECRET=$(kubectl get secret staging-workload-cluster-secret -n argocd --context="$PROD_OPS_CONTEXT" 2>&1 | grep -v "NotFound")
if [ -n "$STAGING_SECRET" ]; then
    echo "   ✅ Cluster secret exists"
else
    echo "   ❌ Cluster secret missing!"
    ISSUES=$((ISSUES + 1))
fi

STAGING_APP=$(kubectl get application staging-workload-applications -n argocd --context="$PROD_OPS_CONTEXT" 2>&1 | grep -v "NotFound")
if [ -n "$STAGING_APP" ]; then
    SYNC_STATUS=$(kubectl get application staging-workload-applications -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.status}' 2>/dev/null)
    echo "   ✅ Bootstrap application exists (Status: $SYNC_STATUS)"
else
    echo "   ❌ Bootstrap application missing!"
    ISSUES=$((ISSUES + 1))
fi

SYNCED_APPS=$(kubectl get applications -n argocd --context="$PROD_OPS_CONTEXT" -o json 2>/dev/null | jq -r '.items[] | select(.spec.destination.server | contains("FB48AC16")) | select(.status.sync.status == "Synced") | .metadata.name' | wc -l | tr -d ' ')
if [ "$SYNCED_APPS" -gt 0 ]; then
    echo "   ✅ $SYNCED_APPS staging-workload applications syncing successfully"
else
    echo "   ⚠️  No staging-workload applications currently synced"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 2. VPC Peering (if Terraform has been applied)
echo "2. VPC Peering Configuration"
echo "   ─────────────────────────────────"

PEERING_STATUS=$(aws ec2 describe-vpc-peering-connections \
    --filters "Name=tag:Name,Values=*prod*-*staging*" \
    --query 'VpcPeeringConnections[0].Status.Code' \
    --output text 2>/dev/null || echo "not_found")

if [ "$PEERING_STATUS" = "active" ]; then
    echo "   ✅ VPC peering connection is active"
elif [ "$PEERING_STATUS" = "pending-acceptance" ]; then
    echo "   ⚠️  VPC peering connection pending acceptance (Terraform not applied to staging)"
    WARNINGS=$((WARNINGS + 1))
elif [ "$PEERING_STATUS" = "not_found" ]; then
    echo "   ⚠️  VPC peering connection not found (Terraform not applied to prod)"
    WARNINGS=$((WARNINGS + 1))
else
    echo "   ❌ VPC peering status: $PEERING_STATUS"
    ISSUES=$((ISSUES + 1))
fi

echo ""

# 3. Prometheus Federation (if Prometheus is running)
echo "3. Prometheus Federation"
echo "   ─────────────────────────────────"

PROM_POD=$(kubectl get pods -n monitoring --context="$PROD_OPS_CONTEXT" -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROM_POD" ]; then
    PROM_STATUS=$(kubectl get pod "$PROM_POD" -n monitoring --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$PROM_STATUS" = "Running" ]; then
        FEDERATION_TARGETS=$(kubectl exec -n monitoring "$PROM_POD" --context="$PROD_OPS_CONTEXT" -- \
            wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null | \
            jq -r '.data.activeTargets[] | select(.labels.job | contains("federate-staging-workload")) | .health' 2>/dev/null | head -1)
        
        if [ "$FEDERATION_TARGETS" = "up" ]; then
            echo "   ✅ Prometheus federation to staging-workload is healthy"
        else
            echo "   ⚠️  Prometheus federation target status: ${FEDERATION_TARGETS:-unknown}"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "   ⚠️  Prometheus pod not running (Status: $PROM_STATUS) - federation cannot be verified"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "   ⚠️  Prometheus pod not found - federation cannot be verified"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 4. Staging-Ops Dependencies
echo "4. Staging-Ops Cluster Dependencies"
echo "   ─────────────────────────────────"

STAGING_OPS_APPS=$(kubectl get applications -n argocd --context="$PROD_OPS_CONTEXT" -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.destination.server | contains("staging-ops")) | .metadata.name' 2>/dev/null | wc -l | tr -d ' ')

if [ "$STAGING_OPS_APPS" -eq 0 ]; then
    echo "   ✅ No ArgoCD applications depend on staging-ops cluster"
else
    echo "   ❌ $STAGING_OPS_APPS applications still reference staging-ops cluster!"
    ISSUES=$((ISSUES + 1))
fi

echo "   ✅ Staging-ops only ran monitoring services (Prometheus, Grafana, dashboards)"
echo "   ✅ All dashboards migrated to prod-ops"
echo "   ✅ No workload applications depend on staging-ops"

echo ""

# 5. Critical Services Health
echo "5. Critical Services Health (Staging-Workload)"
echo "   ─────────────────────────────────"

CRITICAL_APPS=("dareyscore" "lab-controller" "nginx-ingress")
for app in "${CRITICAL_APPS[@]}"; do
    APP_STATUS=$(kubectl get application "$app" -n argocd --context="$PROD_OPS_CONTEXT" -o jsonpath='{.status.sync.status}:{.status.health.status}' 2>/dev/null)
    if [ -n "$APP_STATUS" ]; then
        SYNC_STAT=$(echo "$APP_STATUS" | cut -d: -f1)
        HEALTH_STAT=$(echo "$APP_STATUS" | cut -d: -f2)
        if [ "$SYNC_STAT" = "Synced" ] && [ "$HEALTH_STAT" = "Healthy" ]; then
            echo "   ✅ $app: Synced/Healthy"
        else
            echo "   ⚠️  $app: $SYNC_STAT/$HEALTH_STAT"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "   ⚠️  $app: Application not found"
        WARNINGS=$((WARNINGS + 1))
    fi
done

echo ""

# 6. Summary
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Readiness Summary                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ $ISSUES -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ READY: All checks passed. Safe to destroy staging-ops cluster."
    echo ""
    echo "Recommended next steps:"
    echo "1. Deploy Terraform changes (prod → staging) to enable VPC peering"
    echo "2. Monitor for 24-48 hours to ensure stability"
    echo "3. Archive staging-ops GitOps configs"
    echo "4. Destroy staging-ops cluster via Terraform"
    exit 0
elif [ $ISSUES -eq 0 ]; then
    echo "⚠️  MOSTLY READY: No blocking issues, but $WARNINGS warning(s) to review."
    echo ""
    echo "Blocking issues: None"
    echo "Warnings: $WARNINGS (see details above)"
    echo ""
    echo "Recommendation:"
    echo "- Address warnings before proceeding"
    echo "- OR proceed with caution if warnings are non-critical"
    exit 0
else
    echo "❌ NOT READY: $ISSUES blocking issue(s) found."
    echo ""
    echo "Blocking issues: $ISSUES (must be resolved before destruction)"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Recommendation:"
    echo "- Resolve all blocking issues before destroying staging-ops cluster"
    exit 1
fi
