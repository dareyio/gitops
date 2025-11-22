#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse

def query_prometheus(query, base="http://localhost:9091"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== CHECKING METRIC STRUCTURE IN BLUE CLUSTER ===\n")

# Get a sample of the metrics to see their structure
print("1. Sample http_request_duration_seconds_count metrics:")
all_metrics = query_prometheus("http_request_duration_seconds_count")
if all_metrics.get("data", {}).get("result"):
    print(f"   Found {len(all_metrics['data']['result'])} metrics")
    print("\n   Sample metric labels:")
    for r in all_metrics['data']['result'][:3]:
        print(f"\n   Metric labels:")
        for key, value in sorted(r['metric'].items()):
            print(f"      {key}: {value}")
        print(f"   Value: {r['value'][1]}")
else:
    print("   ❌ No metrics found")

# Check what status codes exist
print("\n2. Checking for status label in metrics:")
status_metrics = query_prometheus("http_request_duration_seconds_count{status!=\"\"}")
if status_metrics.get("data", {}).get("result"):
    print(f"   ✅ Found {len(status_metrics['data']['result'])} metrics with status label")
    statuses = set()
    for r in status_metrics['data']['result']:
        statuses.add(r['metric'].get('status', 'N/A'))
    print(f"   Status codes found: {sorted(statuses)}")
    
    # Show sample with status
    print("\n   Sample metrics with status:")
    for r in status_metrics['data']['result'][:5]:
        print(f"      Status: {r['metric'].get('status')}, Handler: {r['metric'].get('handler', 'N/A')}, Method: {r['metric'].get('method', 'N/A')}")
else:
    print("   ❌ No metrics with status label found")
    print("   This means the status label is missing from the metrics!")

# Check all available labels
print("\n3. All available labels in metrics:")
if all_metrics.get("data", {}).get("result"):
    all_labels = set()
    for r in all_metrics['data']['result']:
        all_labels.update(r['metric'].keys())
    print(f"   Labels: {sorted(all_labels)}")

# Check for error metrics using different label names
print("\n4. Checking for error-related labels:")
if all_metrics.get("data", {}).get("result"):
    error_labels = ['status', 'code', 'http_status', 'status_code', 'error', 'result']
    found_labels = []
    for r in all_metrics['data']['result']:
        for label in error_labels:
            if label in r['metric'] and r['metric'][label]:
                if label not in found_labels:
                    found_labels.append(label)
    if found_labels:
        print(f"   ✅ Found error-related labels: {found_labels}")
    else:
        print("   ❌ No error-related labels found")

print("\n=== CONCLUSION ===")
if not status_metrics.get("data", {}).get("result"):
    print("❌ The 'status' label is MISSING from http_request_duration_seconds_count metrics")
    print("   This is why the dashboard shows no data!")
    print("   The prometheus_fastapi_instrumentator may not be configured correctly")
    print("   or the metrics are not being exposed with status codes")

