# FinOps Dashboard Deep Diagnosis Report

## Executive Summary

The AWS Cost & FinOps Dashboard is showing "No data" because of multiple configuration issues and mismatches between the dashboard queries, the exporter implementation, and the data flow architecture.

## 1. Dashboard Configuration

### Location
- **File**: `gitops/argocd/applications/prod-ops/dashboards/finops/aws-cost-dashboard.yaml`
- **Namespace**: `monitoring`
- **Dashboard UID**: `aws-cost-finops`
- **Title**: "AWS Cost & FinOps Dashboard"

### Data Source Configuration
- **Primary Datasource**: `thanos-query` (UID: `thanos-query`)
- **Datasource Type**: Prometheus
- **Datasource URL**: `http://thanos-query.monitoring.svc:9090` (configured in Grafana)
- **Default Datasource**: Yes (Thanos Query is set as default in Grafana config)

### Dashboard Queries
The dashboard queries the following Prometheus metrics:

1. **Current Month Spend**: `sum(aws_cost_exporter_current_month_cost) by (currency)`
2. **Remaining Credits**: `aws_cost_exporter_remaining_credits`
3. **Daily Average Spend**: `avg_over_time(aws_cost_exporter_daily_cost[30d])`
4. **Forecasted Monthly Spend**: `aws_cost_exporter_forecasted_monthly_cost`
5. **Daily Cost Trend**: `aws_cost_exporter_daily_cost`
6. **Monthly Cost Trend**: `aws_cost_exporter_current_month_cost`
7. **Cost by Service**: `sum(aws_cost_exporter_service_cost) by (service_name)`
8. **Top Spending Services**: `topk(10, sum(aws_cost_exporter_service_cost) by (service_name))`
9. **Cost by Cluster/Environment**: `sum(aws_cost_exporter_cluster_cost) by (cluster)` ⚠️ **ISSUE**

## 2. AWS Cost Exporter Configuration

### Deployment Architecture

There are **TWO conflicting ArgoCD applications** with the same name:

#### Application 1: Helm Chart (Potentially Inactive)
- **File**: `gitops/argocd/applications/prod-ops/applications/aws-cost-exporter.yaml`
- **Type**: Helm Chart from `grafana/helm-charts`
- **Chart**: `aws-cost-exporter` version `0.1.0`
- **Target Namespace**: `monitoring`
- **Image**: `prom/cloudwatch-exporter:latest`
- **Service Port**: `9106`
- **ServiceMonitor**: Enabled, interval `1h`, labels `release: kube-prometheus-stack`

#### Application 2: Custom YAML (Likely Active)
- **File**: `gitops/argocd/applications/prod-ops/applications/aws-cost-exporter-app.yaml`
- **Type**: Directory-based ArgoCD Application
- **Source Path**: `argocd/applications/prod-ops/applications/aws-cost-exporter`
- **Target Namespace**: `finops`
- **Manifest**: `aws-cost-exporter-custom.yaml`

### Custom Exporter Implementation

**Location**: `gitops/argocd/applications/prod-ops/applications/aws-cost-exporter/aws-cost-exporter-custom.yaml`

**Key Details**:
- **Namespace**: `finops` (NOT `monitoring`)
- **Image**: `python:3.11-slim`
- **Implementation**: Embedded Python script using `boto3` and `prometheus-client`
- **Metrics Port**: `8080`
- **Service**: ClusterIP on port `8080`
- **ServiceMonitor**: 
  - Namespace: `finops`
  - Labels: `app: aws-cost-exporter`, `release: kube-prometheus-stack`
  - Interval: `1h`
  - Path: `/metrics`
  - Port: `metrics` (8080)

**Exposed Metrics**:
1. ✅ `aws_cost_exporter_current_month_cost{currency}`
2. ✅ `aws_cost_exporter_daily_cost{date, currency}`
3. ✅ `aws_cost_exporter_forecasted_monthly_cost{currency}`
4. ✅ `aws_cost_exporter_service_cost{service_name, currency}`
5. ✅ `aws_cost_exporter_remaining_credits`
6. ❌ `aws_cost_exporter_cluster_cost{cluster}` - **NOT EXPOSED** ⚠️

### Metric Mismatch Issue

**Critical Finding**: The dashboard queries for `aws_cost_exporter_cluster_cost` (panel "Cost by Cluster/Environment"), but the exporter **does not expose this metric**. This will always return "No data" for that panel.

## 3. Data Flow Architecture

### Expected Data Flow

```
AWS Cost Explorer API
    ↓
AWS Cost Exporter (finops namespace)
    ↓ (exposes metrics on :8080/metrics)
Service (aws-cost-exporter.finops.svc:8080)
    ↓ (scraped by)
Prometheus (ops cluster, monitoring namespace)
    ↓ (remoteWrite to)
Thanos Receive (monitoring namespace)
    ↓ (queried by)
Thanos Query (monitoring namespace)
    ↓ (queried by)
Grafana Dashboard (via thanos-query datasource)
```

### Prometheus Configuration

**Location**: `gitops/argocd/applications/prod-ops/applications/kube-prometheus-stack.yaml`

**Key Settings**:
- **Namespace**: `monitoring`
- **Retention**: `30d`
- **External Labels**: `cluster: ops`, `prometheus_replica: $(POD_NAME)`
- **Remote Write**: `http://thanos-receive.monitoring.svc:10902/api/v1/receive`
- **ServiceMonitor Discovery**: No explicit `serviceMonitorSelector` configured (uses defaults)

**ServiceMonitor Discovery**:
- By default, Prometheus Operator discovers ServiceMonitors from **all namespaces**
- ServiceMonitors are selected based on labels matching `release: kube-prometheus-stack`
- The ServiceMonitor in `finops` namespace has label `release: kube-prometheus-stack` ✅

**Potential Issue**: If Prometheus Operator has a restrictive `serviceMonitorSelector`, it might not discover ServiceMonitors in the `finops` namespace. However, the configuration shows no explicit restrictions, so it should discover them.

### Thanos Configuration

**Location**: `gitops/argocd/applications/prod-ops/applications/thanos.yaml`

**Thanos Query**:
- **Store Endpoints**: `thanos-receive.monitoring.svc.cluster.local:10901`
- **Service**: `thanos-query.monitoring.svc:9090`
- **Querying**: Thanos Receive (which receives metrics from Prometheus via remoteWrite)

**Thanos Receive**:
- Receives metrics from Prometheus instances via remoteWrite
- Aggregates metrics from:
  - Ops cluster Prometheus (monitoring namespace)
  - Blue cluster Prometheus (via remoteWrite)
  - Green cluster Prometheus (via remoteWrite)

## 4. Grafana Configuration

**Location**: `gitops/argocd/applications/prod-ops/applications/grafana.yaml`

**Datasources**:
1. **Prometheus (Ops)**: `http://kube-prometheus-stack-prometheus.monitoring.svc:9090` (UID: `prometheus-ops`)
2. **Thanos Query**: `http://thanos-query.monitoring.svc:9090` (UID: `thanos-query`) ⭐ **DEFAULT**
3. **Loki**: `http://loki.monitoring.svc:3100`
4. **Tempo**: `http://tempo.observability.svc:3200`

**Dashboard Discovery**:
- Grafana sidecar discovers dashboards from ConfigMaps with label `grafana_dashboard: "1"`
- Search namespace: `monitoring`
- Dashboard ConfigMap: `grafana-dashboard-aws-cost` in `monitoring` namespace ✅

## 5. Identified Issues

### Issue 1: Missing Metric - `aws_cost_exporter_cluster_cost`
**Severity**: High
**Impact**: "Cost by Cluster/Environment" panel will always show "No data"
**Root Cause**: Dashboard queries for `aws_cost_exporter_cluster_cost{cluster}`, but exporter doesn't expose this metric
**Location**: Dashboard panel at line 353

### Issue 2: Namespace Mismatch
**Severity**: Medium
**Impact**: Potential confusion, but should work if Prometheus discovers ServiceMonitors from all namespaces
**Details**: 
- Exporter deployed in `finops` namespace
- Prometheus in `monitoring` namespace
- ServiceMonitor in `finops` namespace with label `release: kube-prometheus-stack`
- Should work if Prometheus Operator discovers from all namespaces (default behavior)

### Issue 3: ArgoCD Application Conflict
**Severity**: Medium
**Impact**: Two applications with same name could cause deployment conflicts
**Details**:
- `aws-cost-exporter.yaml` (Helm chart, deploys to `monitoring`)
- `aws-cost-exporter-app.yaml` (Custom YAML, deploys to `finops`)
- Both have same name: `aws-cost-exporter` in `argocd` namespace
- Only one can be active at a time

### Issue 4: ServiceMonitor Namespace Selector
**Severity**: Low (if Prometheus discovers from all namespaces)
**Impact**: ServiceMonitor doesn't have explicit `namespaceSelector`, but this is fine since service is in same namespace
**Details**: ServiceMonitor in `finops` namespace will discover service in `finops` namespace (correct)

### Issue 5: Scrape Interval
**Severity**: Low
**Impact**: Metrics update every 1 hour, so dashboard might show stale data
**Details**: ServiceMonitor configured with `interval: 1h`, which matches exporter's update frequency

## 6. Data Flow Verification Checklist

To verify the data flow, check:

1. ✅ **Exporter Pod Running**: Check if `aws-cost-exporter` pod is running in `finops` namespace
2. ✅ **Exporter Metrics Exposed**: Check if `http://aws-cost-exporter.finops.svc:8080/metrics` returns metrics
3. ✅ **ServiceMonitor Created**: Check if ServiceMonitor exists in `finops` namespace
4. ✅ **Prometheus Target Discovery**: Check if Prometheus has discovered the exporter as a target
5. ✅ **Prometheus Scraping**: Check if Prometheus is successfully scraping the exporter
6. ✅ **Remote Write Working**: Check if Prometheus is writing metrics to Thanos Receive
7. ✅ **Thanos Query Access**: Check if Thanos Query can query the metrics
8. ✅ **Grafana Datasource**: Check if Grafana can query Thanos Query

## 7. Missing Metrics Analysis

### Metrics Exposed by Exporter:
- `aws_cost_exporter_current_month_cost{currency}`
- `aws_cost_exporter_daily_cost{date, currency}`
- `aws_cost_exporter_forecasted_monthly_cost{currency}`
- `aws_cost_exporter_service_cost{service_name, currency}`
- `aws_cost_exporter_remaining_credits`

### Metrics Queried by Dashboard:
- ✅ `aws_cost_exporter_current_month_cost` - **EXISTS**
- ✅ `aws_cost_exporter_remaining_credits` - **EXISTS**
- ✅ `aws_cost_exporter_daily_cost` - **EXISTS**
- ✅ `aws_cost_exporter_forecasted_monthly_cost` - **EXISTS**
- ✅ `aws_cost_exporter_service_cost` - **EXISTS**
- ❌ `aws_cost_exporter_cluster_cost` - **MISSING** ⚠️

## 8. Cluster/Environment Cost Metric

The dashboard expects `aws_cost_exporter_cluster_cost{cluster}` to show costs broken down by cluster (ops, blue, green). However:

1. The exporter doesn't expose this metric
2. The exporter only queries AWS Cost Explorer API, which doesn't provide cluster-level breakdown by default
3. To implement this, the exporter would need to:
   - Query AWS Cost Explorer with tags/dimensions for cluster
   - Or aggregate costs from different AWS accounts (if clusters are in different accounts)
   - Or use AWS Cost Allocation Tags to identify cluster costs

## 9. Recommendations for Investigation

1. **Check Exporter Pod Status**: Verify pod is running and healthy
2. **Check Exporter Logs**: Look for AWS API errors or metric generation issues
3. **Check Prometheus Targets**: Verify Prometheus has discovered and is scraping the exporter
4. **Check Prometheus Metrics**: Query Prometheus directly to see if metrics exist
5. **Check Thanos Query**: Query Thanos Query to see if metrics are available
6. **Check ServiceMonitor**: Verify ServiceMonitor is properly configured and discovered
7. **Check Namespace Permissions**: Verify Prometheus can access ServiceMonitors in `finops` namespace
8. **Check AWS IAM Permissions**: Verify the IAM role has permissions to query Cost Explorer API
9. **Check Metric Names**: Verify metric names match exactly (case-sensitive)
10. **Check Time Range**: Verify dashboard time range includes when metrics were collected

## 10. Configuration Summary

| Component | Location | Namespace | Status |
|-----------|----------|-----------|--------|
| Dashboard | ConfigMap | monitoring | ✅ Configured |
| Grafana | Deployment | monitoring | ✅ Configured |
| Thanos Query | Service | monitoring | ✅ Configured |
| Prometheus | Deployment | monitoring | ✅ Configured |
| Exporter | Deployment | finops | ⚠️ Needs verification |
| ServiceMonitor | Resource | finops | ⚠️ Needs verification |
| Service | Service | finops | ⚠️ Needs verification |

## 11. Next Steps for Verification

1. Check if exporter pod is running: `kubectl get pods -n finops -l app=aws-cost-exporter`
2. Check exporter metrics endpoint: `kubectl port-forward -n finops svc/aws-cost-exporter 8080:8080` then `curl http://localhost:8080/metrics`
3. Check Prometheus targets: Access Prometheus UI and check `/targets` endpoint
4. Check ServiceMonitor: `kubectl get servicemonitor -n finops aws-cost-exporter -o yaml`
5. Check Prometheus configuration: `kubectl get prometheus -n monitoring -o yaml`
6. Query Thanos Query directly: `curl "http://thanos-query.monitoring.svc:9090/api/v1/query?query=aws_cost_exporter_current_month_cost"`

---

**Report Generated**: $(date)
**Investigation Scope**: Deep diagnosis of FinOps dashboard "No data" issue
**Status**: Fact-gathering complete, ready for verification steps

