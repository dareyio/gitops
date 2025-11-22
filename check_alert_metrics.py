#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse

def query_prometheus(query, base="http://localhost:10903"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== CHECKING ALERT METRICS ===\n")

# Check what job labels exist for lab-controller
print("1. Checking 'up' metric for lab-controller...")
up_query = 'up{namespace="lab-controller"}'
up_result = query_prometheus(up_query)

if up_result.get("data", {}).get("result"):
    print(f"   ✅ Found {len(up_result['data']['result'])} metrics")
    print("   Job labels found:")
    jobs = set()
    for r in up_result['data']['result']:
        job = r['metric'].get('job', 'N/A')
        jobs.add(job)
        cluster = r['metric'].get('cluster', 'N/A')
        value = r['value'][1]
        print(f"      Job: {job}, Cluster: {cluster}, Value: {value}")
    print(f"\n   Unique jobs: {sorted(jobs)}")
else:
    print("   ❌ No 'up' metrics found for lab-controller namespace")

# Check the actual alert query
print("\n2. Testing alert query...")
alert_expr = 'up{job=~"lab-controller.*", namespace="lab-controller"} == 0'
alert_test = query_prometheus(alert_expr)

if alert_test.get("data", {}).get("result"):
    print(f"   ✅ Alert query returned {len(alert_test['data']['result'])} results (should be > 0 if pods are down)")
    for r in alert_test['data']['result']:
        print(f"      {r['metric']}: {r['value'][1]}")
else:
    print("   ⚠️  Alert query returned no results")
    print("   This means either:")
    print("   - Pods are not down")
    print("   - Job label doesn't match 'lab-controller.*'")
    print("   - Metrics not available in Thanos")

# Check alternative query
print("\n3. Testing alternative query (any job in namespace)...")
alt_query = 'up{namespace="lab-controller"} == 0'
alt_result = query_prometheus(alt_query)

if alt_result.get("data", {}).get("result"):
    print(f"   ✅ Alternative query found {len(alt_result['data']['result'])} down services")
    for r in alt_result['data']['result']:
        print(f"      Job: {r['metric'].get('job')}, Cluster: {r['metric'].get('cluster')}, Value: {r['value'][1]}")
else:
    print("   ⚠️  No down services found")

print("\n=== RECOMMENDATION ===")
if up_result.get("data", {}).get("result"):
    jobs = [r['metric'].get('job') for r in up_result['data']['result']]
    if jobs and not any('lab-controller' in j for j in jobs):
        print("⚠️  Job label doesn't contain 'lab-controller'")
        print(f"   Actual jobs: {set(jobs)}")
        print("   Alert query may need to be updated to match actual job labels")

