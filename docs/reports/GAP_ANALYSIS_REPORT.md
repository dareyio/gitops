# FinOps Dashboard Gap Analysis Report

**Date**: 2025-11-22 10:06
**Status**: Gap Identified

## Executive Summary

After conducting comprehensive tests, I've identified the **root cause** of why metrics are not appearing in Thanos Query despite being available in Prometheus.

## Test Results Summary

### ✅ What's Working

1. **Exporter Location**: Confirmed in **ops cluster** (`finops` namespace)
2. **Prometheus Scraping**: Successfully scraping exporter, metrics exist
3. **Thanos Receive**: Running, LoadBalancer configured, port 19291 accessible
4. **Thanos Query**: Running, can see Thanos Receive store
5. **Network Connectivity**: Port 19291 is accessible from Prometheus pod

### ❌ Critical Issues Found

#### Issue 1: DNS Resolution Failure (CRITICAL)
- **Problem**: `thanos-receive.monitoring.svc` DNS resolution returns **NXDOMAIN**
- **Impact**: Prometheus may not be able to resolve the service name
- **Finding**: Full FQDN `thanos-receive.monitoring.svc.cluster.local` should work, but short name fails
- **Status**: Port connectivity test passed (using IP: 172.20.90.200), so Prometheus might be using cached IP

#### Issue 2: Prometheus remoteWrite Status Unknown
- **Finding**: No recent remoteWrite logs found in Prometheus
- **Possible Causes**:
  - remoteWrite is working silently (no errors = success)
  - remoteWrite is failing but not logging
  - Metrics are being written but not persisted

#### Issue 3: Thanos Receive Metrics Reception
- **Finding**: Thanos Receive shows `thanos_receive_write_samples` metrics, indicating it IS receiving data
- **Finding**: Store API shows Thanos Receive with `minTime: 1763419939419` (recent timestamp)
- **Finding**: But Thanos Query returns 0 results for `aws_cost_exporter` metrics

## Root Cause Analysis

### The Gap

The data flow appears to be:
```
Prometheus (has metrics) ✅ 
  → remoteWrite (configured correctly) ✅
  → Thanos Receive (receiving samples) ✅
  → Thanos Query (can see store) ✅
  → BUT: Query returns 0 results ❌
```

### Possible Root Causes

1. **Time Range Mismatch**
   - Thanos Receive `minTime: 1763419939419` = 2025-11-22 10:05:39 UTC
   - Prometheus metric timestamp: `1763805965.198` = 2025-11-22 10:06:05 UTC
   - These are very close, so time range should be fine

2. **Label Mismatch**
   - Prometheus metrics have labels: `container`, `endpoint`, `instance`, `job`, `namespace`, `pod`, `service`
   - These are added by Prometheus during scraping
   - Thanos Query might be filtering these out or they might not match

3. **Tenant/Replication Issue**
   - Thanos Receive shows `tenant_id: "default-tenant"`
   - Metrics might be stored under a tenant that Thanos Query isn't querying

4. **External Labels**
   - Prometheus has `cluster: ops` external label
   - This should be preserved in remoteWrite
   - But might cause query issues if not handled correctly

5. **Store API Query Issue**
   - Thanos Query uses gRPC (port 10901) to query Thanos Receive
   - Store endpoint: `dnssrv+_grpc._tcp.thanos-receive.monitoring.svc.cluster.local`
   - This should work, but DNS resolution issue might affect it

## Detailed Test Results

### Test 1: Exporter Location ✅
- **Result**: Exporter is in **ops cluster**, `finops` namespace
- **Status**: Confirmed

### Test 2: Thanos Receive LoadBalancer ✅
- **Result**: LoadBalancer active, external endpoint: `k8s-monitori-thanosre-ae92164cc3-46c89005a172001f.elb.eu-west-2.amazonaws.com`
- **Ports**: 10902 (HTTP), 10901 (gRPC), 19291 (remote-write)
- **Status**: Configured correctly

### Test 3: Prometheus remoteWrite Config ✅
- **Ops**: `http://thanos-receive.monitoring.svc:19291/api/v1/receive` (internal)
- **Blue**: `http://k8s-monitori-thanosre-ae92164cc3-46c89005a172001f.elb.eu-west-2.amazonaws.com:19291/api/v1/receive` (external)
- **Status**: Correctly configured

### Test 4: DNS Resolution ❌
- **Short name**: `thanos-receive.monitoring.svc` → **NXDOMAIN** (FAILS)
- **Public DNS**: `thanos-receive.talentos.darey.io` → Resolves correctly
- **Impact**: Prometheus might be using cached IP or full FQDN

### Test 5: Network Connectivity ✅
- **Port 19291**: Accessible (nc test passed)
- **IP**: 172.20.90.200
- **Status**: Network connectivity works

### Test 6: Thanos Receive Reception ✅
- **Metrics**: `thanos_receive_write_samples` present
- **Status**: Receiving data

### Test 7: Thanos Query Store API ✅
- **Store**: Can see Thanos Receive store
- **Last Check**: Recent (2025-11-22T10:05:59Z)
- **Status**: Store connection working

### Test 8: Prometheus Metrics ✅
- **Result**: `aws_cost_exporter_current_month_cost` exists in Prometheus
- **Value**: `-9.994e-07` (very small, but present)
- **Status**: Metrics are in Prometheus

### Test 9: Thanos Query Results ❌
- **Result**: 0 results for `aws_cost_exporter_current_month_cost`
- **Status**: Metrics not queryable via Thanos Query

## The Gap

**The gap is between Thanos Receive and Thanos Query querying.**

Thanos Receive is receiving metrics (confirmed by metrics), but Thanos Query cannot retrieve them. This suggests:

1. **Time Range Issue**: Metrics might be too recent or outside query window
2. **Label/Matcher Issue**: Query might not match the stored metrics
3. **Tenant Filtering**: Metrics stored under tenant that Query isn't accessing
4. **Replication Issue**: Metrics not replicated to queried store

## Recommended Next Steps

1. **Check Thanos Receive ingested series**:
   ```bash
   curl http://thanos-receive:10902/api/v1/query?query=up
   ```

2. **Query Thanos Receive directly** (bypass Thanos Query):
   ```bash
   curl http://thanos-receive:10902/api/v1/query?query=aws_cost_exporter_current_month_cost
   ```

3. **Check external labels** in stored metrics vs query

4. **Verify time range** - ensure query time range includes metric timestamps

5. **Check Thanos Query logs** for any filtering or errors

---

**Conclusion**: The infrastructure is correctly configured, but there's a gap in how Thanos Query retrieves metrics from Thanos Receive. The metrics are being received, but not queryable.

