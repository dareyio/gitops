# Critical Fixes Required for FinOps Dashboard

## Priority 1: Critical Fixes (Must Fix)

### 1. Missing Metric: `aws_cost_exporter_cluster_cost`

**Issue**: Dashboard queries for `aws_cost_exporter_cluster_cost{cluster}` but exporter doesn't expose it.

**Impact**: "Cost by Cluster/Environment" panel will always show "No data".

**Options**:

**Option A: Remove the panel** (Quick fix)
- Remove or disable the "Cost by Cluster/Environment" panel from the dashboard
- File: `gitops/argocd/applications/prod-ops/dashboards/finops/aws-cost-dashboard.yaml`
- Line: ~343-378

**Option B: Implement the metric** (Proper fix)
- Add `aws_cost_exporter_cluster_cost{cluster}` metric to the exporter
- Requires querying AWS Cost Explorer with cluster tags/dimensions
- File: `gitops/argocd/applications/prod-ops/applications/aws-cost-exporter/aws-cost-exporter-custom.yaml`
- Challenge: AWS Cost Explorer doesn't provide cluster breakdown by default - requires:
  - AWS Cost Allocation Tags configured on resources
  - Or querying multiple AWS accounts (if clusters in different accounts)
  - Or using AWS Resource Groups with cluster tags

**Recommendation**: Start with Option A (remove panel) to get dashboard working, then implement Option B if cluster-level cost breakdown is needed.

---

### 2. ArgoCD Application Conflict

**Issue**: Two ArgoCD applications with the same name `aws-cost-exporter` in `argocd` namespace.

**Files**:
1. `gitops/argocd/applications/prod-ops/applications/aws-cost-exporter.yaml` (Helm chart)
2. `gitops/argocd/applications/prod-ops/applications/aws-cost-exporter-app.yaml` (Custom YAML)

**Impact**: 
- Only one can be active at a time
- Could cause deployment conflicts
- Unclear which one is actually deployed

**Fix**: Remove the unused application

**Decision Required**: Which application should be kept?
- **Custom YAML** (`aws-cost-exporter-app.yaml`): Currently deployed to `finops` namespace, uses Python script
- **Helm Chart** (`aws-cost-exporter.yaml`): Would deploy to `monitoring` namespace, uses `prom/cloudwatch-exporter`

**Recommendation**: Keep the custom YAML application (it's the one currently working) and remove the Helm chart application.

**Action**: Delete `gitops/argocd/applications/prod-ops/applications/aws-cost-exporter.yaml`

---

### 3. Verify Data Flow End-to-End

**Issue**: Unknown if metrics are actually being collected, scraped, and available in Thanos Query.

**Verification Steps Required**:

1. **Check Exporter Pod Status**
   ```bash
   kubectl get pods -n finops -l app=aws-cost-exporter
   kubectl logs -n finops -l app=aws-cost-exporter --tail=50
   ```

2. **Check Exporter Metrics Endpoint**
   ```bash
   kubectl port-forward -n finops svc/aws-cost-exporter 8080:8080
   curl http://localhost:8080/metrics | grep aws_cost_exporter
   ```

3. **Check ServiceMonitor**
   ```bash
   kubectl get servicemonitor -n finops aws-cost-exporter -o yaml
   ```

4. **Check Prometheus Targets**
   - Access Prometheus UI: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`
   - Navigate to Status → Targets
   - Look for `aws-cost-exporter` target in `finops` namespace
   - Verify it's UP and being scraped

5. **Check Prometheus Metrics**
   - In Prometheus UI, query: `aws_cost_exporter_current_month_cost`
   - Verify metrics exist and have values

6. **Check Thanos Query**
   ```bash
   kubectl port-forward -n monitoring svc/thanos-query 9090:9090
   curl "http://localhost:9090/api/v1/query?query=aws_cost_exporter_current_month_cost"
   ```

7. **Check AWS IAM Permissions**
   - Verify IAM role has permissions for Cost Explorer API
   - Role: `arn:aws:iam::586794457112:role/darey-io-v2-lab-prod-ops-aws-cost-exporter-role`
   - Required permissions: `ce:GetCostAndUsage`, `ce:GetDimensionValues`, `ce:GetUsageReport`

**If any step fails, that's the root cause and must be fixed.**

---

## Priority 2: Important but Not Blocking

### 4. ServiceMonitor Namespace Discovery

**Issue**: ServiceMonitor is in `finops` namespace, Prometheus is in `monitoring` namespace.

**Status**: Should work by default (Prometheus Operator discovers ServiceMonitors from all namespaces), but needs verification.

**Fix**: If Prometheus isn't discovering the ServiceMonitor, add explicit namespace selector to Prometheus configuration OR move ServiceMonitor to `monitoring` namespace.

---

### 5. Dashboard Time Range

**Issue**: Dashboard time range is `now-30d` to `now`, but metrics might not have 30 days of history.

**Impact**: Some panels might show "No data" if metrics don't have enough history.

**Fix**: Adjust time range or verify metrics have sufficient history.

---

## Summary of Critical Actions

1. ✅ **Fix Missing Metric**: Remove `aws_cost_exporter_cluster_cost` panel OR implement the metric
2. ✅ **Resolve ArgoCD Conflict**: Remove unused `aws-cost-exporter.yaml` application
3. ✅ **Verify Data Flow**: Run verification steps to identify where the pipeline breaks
4. ⚠️ **Fix Any Broken Steps**: Address any issues found during verification

---

## Quick Win: Remove Problematic Panel

The fastest way to get the dashboard working is to remove the "Cost by Cluster/Environment" panel that queries the non-existent metric. This will allow all other panels to work (assuming the data flow is functioning).

**File to edit**: `gitops/argocd/applications/prod-ops/dashboards/finops/aws-cost-dashboard.yaml`
**Action**: Remove or comment out the panel at lines 343-378

---

## Next Steps

1. **Immediate**: Remove ArgoCD application conflict (delete unused app)
2. **Immediate**: Remove or fix the `aws_cost_exporter_cluster_cost` panel
3. **Immediate**: Run verification steps to identify data flow issues
4. **Follow-up**: Fix any issues found during verification
5. **Future**: Implement `aws_cost_exporter_cluster_cost` metric if cluster-level breakdown is needed

