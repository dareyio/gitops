#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse

def query_prometheus(query, base="http://localhost:10902"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

def get_label_values(label_name, base="http://localhost:10902"):
    try:
        url = f"{base}/api/v1/label/{label_name}/values"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== CHECKING AVAILABLE METRICS FOR DASHBOARD ===\n")

# Check if kube_namespace_labels exists
print("1. Checking kube_namespace_labels...")
kube_ns = query_prometheus("kube_namespace_labels")
if kube_ns.get("data", {}).get("result"):
    print(f"   ✅ Found {len(kube_ns['data']['result'])} kube_namespace_labels metrics")
    namespaces = set()
    for r in kube_ns['data']['result']:
        namespaces.add(r['metric'].get('namespace', 'N/A'))
    print(f"   Namespaces: {sorted(namespaces)[:10]}")
else:
    print("   ❌ kube_namespace_labels not found")

# Check namespace label values
print("\n2. Checking namespace label values...")
ns_values = get_label_values("namespace")
if ns_values.get("data"):
    print(f"   ✅ Found {len(ns_values['data'])} namespaces")
    print(f"   Sample: {sorted(ns_values['data'])[:10]}")
else:
    print("   ❌ Could not get namespace values")

# Check if up metric has service label
print("\n3. Checking 'up' metric for service/job labels...")
up_metrics = query_prometheus("up")
if up_metrics.get("data", {}).get("result"):
    print(f"   ✅ Found {len(up_metrics['data']['result'])} up metrics")
    # Check what labels exist
    sample = up_metrics['data']['result'][0] if up_metrics['data']['result'] else {}
    labels = sample.get('metric', {}).keys()
    print(f"   Available labels in 'up': {sorted(labels)}")
    has_service = 'service' in labels
    has_job = 'job' in labels
    print(f"   Has 'service' label: {has_service}")
    print(f"   Has 'job' label: {has_job}")
else:
    print("   ❌ up metric not found")

# Check http_request_duration_seconds_count for available labels
print("\n4. Checking http_request_duration_seconds_count labels...")
http_metrics = query_prometheus("http_request_duration_seconds_count")
if http_metrics.get("data", {}).get("result"):
    print(f"   ✅ Found {len(http_metrics['data']['result'])} metrics")
    sample = http_metrics['data']['result'][0] if http_metrics['data']['result'] else {}
    labels = sample.get('metric', {}).keys()
    print(f"   Available labels: {sorted(labels)}")
    
    # Check namespaces in this metric
    namespaces = set()
    services = set()
    jobs = set()
    for r in http_metrics['data']['result'][:50]:
        namespaces.add(r['metric'].get('namespace', ''))
        if r['metric'].get('service'):
            services.add(r['metric'].get('service'))
        if r['metric'].get('job'):
            jobs.add(r['metric'].get('job'))
    print(f"   Namespaces in metric: {sorted([n for n in namespaces if n])[:10]}")
    print(f"   Services in metric: {sorted(services)[:10]}")
    print(f"   Jobs in metric: {sorted(jobs)[:10]}")
else:
    print("   ❌ http_request_duration_seconds_count not found")

print("\n=== RECOMMENDATIONS ===")
print("Based on findings, dashboard should use:")
if http_metrics.get("data", {}).get("result"):
    print("  - Namespace variable: label_values(http_request_duration_seconds_count, namespace)")
    if services:
        print("  - Application variable: label_values(http_request_duration_seconds_count{namespace=~\"$namespace\"}, service)")
    elif jobs:
        print("  - Application variable: label_values(http_request_duration_seconds_count{namespace=~\"$namespace\"}, job)")

