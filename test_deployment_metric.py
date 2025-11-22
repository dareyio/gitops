#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse

def query(query, base="http://localhost:9094"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== TESTING DEPLOYMENT METRIC ===\n")

# Test 1: Check if metric exists at all
print("1. Checking if kube_deployment_status_replicas_available exists...")
result = query('kube_deployment_status_replicas_available')
if result.get("data", {}).get("result"):
    print(f"   ✅ Metric exists! Found {len(result['data']['result'])} results")
    # Show sample
    for r in result['data']['result'][:3]:
        ns = r['metric'].get('namespace', 'N/A')
        deploy = r['metric'].get('deployment', 'N/A')
        cluster = r['metric'].get('cluster', 'N/A')
        value = r['value'][1]
        print(f"      Namespace: {ns}, Deployment: {deploy}, Cluster: {cluster}, Value: {value}")
else:
    print("   ❌ Metric does not exist")

# Test 2: Check for lab-controller specifically
print("\n2. Checking for lab-controller deployment...")
result = query('kube_deployment_status_replicas_available{deployment="lab-controller"}')
if result.get("data", {}).get("result"):
    print(f"   ✅ Found {len(result['data']['result'])} lab-controller deployments:")
    for r in result['data']['result']:
        ns = r['metric'].get('namespace', 'N/A')
        cluster = r['metric'].get('cluster', 'N/A')
        value = r['value'][1]
        print(f"      Namespace: {ns}, Cluster: {cluster}, Available: {value}")
else:
    print("   ❌ No lab-controller deployment found")

# Test 3: Check with namespace filter
print("\n3. Checking with namespace filter...")
result = query('kube_deployment_status_replicas_available{namespace="lab-controller"}')
if result.get("data", {}).get("result"):
    print(f"   ✅ Found {len(result['data']['result'])} deployments in lab-controller namespace:")
    for r in result['data']['result']:
        deploy = r['metric'].get('deployment', 'N/A')
        cluster = r['metric'].get('cluster', 'N/A')
        value = r['value'][1]
        print(f"      Deployment: {deploy}, Cluster: {cluster}, Available: {value}")
else:
    print("   ❌ No deployments found in lab-controller namespace")

# Test 4: Check all namespaces
print("\n4. Checking what namespaces have this metric...")
result = query('kube_deployment_status_replicas_available')
if result.get("data", {}).get("result"):
    namespaces = set()
    for r in result['data']['result']:
        namespaces.add(r['metric'].get('namespace', 'N/A'))
    print(f"   Namespaces with metric: {sorted(namespaces)[:10]}")

print("\n=== RECOMMENDATION ===")
print("If metric doesn't exist, the alert query needs to be updated.")
print("Alternative: Use kube_pod_status_phase or check if metric exists in blue cluster's Prometheus")

