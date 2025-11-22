#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse

def query_thanos(query, base="http://localhost:10902"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== CHECKING THANOS QUERY FOR ERROR DATA ===\n")
print("(Thanos aggregates data from all clusters - blue, green, ops)\n")

# Check if metric exists
print("1. Checking if http_request_duration_seconds_count exists in Thanos...")
all_metrics = query_thanos("http_request_duration_seconds_count")
if all_metrics.get("data", {}).get("result"):
    print(f"   ✅ Found {len(all_metrics['data']['result'])} metrics")
    # Group by cluster
    clusters = {}
    for r in all_metrics['data']['result']:
        cluster = r['metric'].get('cluster', 'N/A')
        clusters[cluster] = clusters.get(cluster, 0) + 1
    print("   By Cluster:")
    for cluster, count in sorted(clusters.items()):
        print(f"      {cluster}: {count} metrics")
    # Show sample
    for r in all_metrics['data']['result'][:5]:
        ns = r['metric'].get('namespace', 'N/A')
        cluster = r['metric'].get('cluster', 'N/A')
        status = r['metric'].get('status', 'N/A')
        service = r['metric'].get('service', r['metric'].get('job', 'N/A'))
        print(f"      Cluster: {cluster}, NS: {ns}, Status: {status}, Service: {service}")
else:
    print("   ❌ Metric http_request_duration_seconds_count does not exist in Thanos")

# Check 4xx errors
print("\n2. Checking 4xx errors in Thanos...")
fourxx = query_thanos('http_request_duration_seconds_count{status=~"4.."}')
if fourxx.get("data", {}).get("result"):
    print(f"   ✅ Found {len(fourxx['data']['result'])} 4xx error metrics")
    for r in fourxx['data']['result'][:5]:
        cluster = r['metric'].get('cluster', 'N/A')
        status = r['metric'].get('status', 'N/A')
        ns = r['metric'].get('namespace', 'N/A')
        service = r['metric'].get('service', r['metric'].get('job', 'N/A'))
        print(f"      Cluster: {cluster}, Status: {status}, NS: {ns}, Service: {service}")
else:
    print("   ❌ No 4xx error metrics found in Thanos")

# Check 5xx errors
print("\n3. Checking 5xx errors in Thanos...")
fivexx = query_thanos('http_request_duration_seconds_count{status=~"5.."}')
if fivexx.get("data", {}).get("result"):
    print(f"   ✅ Found {len(fivexx['data']['result'])} 5xx error metrics")
    for r in fivexx['data']['result'][:5]:
        cluster = r['metric'].get('cluster', 'N/A')
        status = r['metric'].get('status', 'N/A')
        ns = r['metric'].get('namespace', 'N/A')
        service = r['metric'].get('service', r['metric'].get('job', 'N/A'))
        print(f"      Cluster: {cluster}, Status: {status}, NS: {ns}, Service: {service}")
else:
    print("   ❌ No 5xx error metrics found in Thanos")

# Check error rate
print("\n4. Checking error rate in Thanos...")
error_rate = query_thanos('sum(rate(http_request_duration_seconds_count{status=~"[45].."}[5m])) by (status, cluster)')
if error_rate.get("data", {}).get("result"):
    print("   ✅ Error Rate by Status and Cluster:")
    for r in error_rate['data']['result']:
        status = r['metric'].get('status', 'N/A')
        cluster = r['metric'].get('cluster', 'N/A')
        value = float(r['value'][1])
        print(f"      {cluster}/{status}: {value:.6f} req/s")
else:
    print("   ❌ No error rate data found in Thanos")

print("\n=== SUMMARY ===")
has_errors = (fourxx.get("data", {}).get("result") or fivexx.get("data", {}).get("result"))
if has_errors:
    print("✅ ERROR DATA IS PRESENT IN THANOS")
    print("   The dashboard should show data if:")
    print("   - Dashboard uses Thanos Query datasource (not Prometheus)")
    print("   - Correct namespace is selected")
    print("   - Correct cluster is selected")
else:
    print("❌ ERROR DATA NOT FOUND IN THANOS")
    print("   This means:")
    print("   - Applications may not be running in any cluster")
    print("   - Applications may not be scraped by Prometheus")
    print("   - Thanos may not be aggregating from all clusters")
    print("   - Error injection may not be reaching the applications")

