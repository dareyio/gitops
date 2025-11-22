#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse

def query_prometheus(query, base="http://localhost:9090"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== CHECKING PROMETHEUS FOR ERROR DATA ===\n")

# Check if metric exists at all
print("1. Checking if http_request_duration_seconds_count exists...")
all_metrics = query_prometheus("http_request_duration_seconds_count")
if all_metrics.get("data", {}).get("result"):
    print(f"   ✅ Found {len(all_metrics['data']['result'])} metrics")
    # Show sample
    for r in all_metrics['data']['result'][:5]:
        ns = r['metric'].get('namespace', 'N/A')
        status = r['metric'].get('status', 'N/A')
        service = r['metric'].get('service', r['metric'].get('job', 'N/A'))
        print(f"      NS: {ns}, Status: {status}, Service: {service}")
else:
    print("   ❌ Metric http_request_duration_seconds_count does not exist")

# Check 4xx errors
print("\n2. Checking 4xx errors...")
fourxx = query_prometheus('http_request_duration_seconds_count{status=~"4.."}')
if fourxx.get("data", {}).get("result"):
    print(f"   ✅ Found {len(fourxx['data']['result'])} 4xx error metrics")
    for r in fourxx['data']['result'][:5]:
        print(f"      Status: {r['metric'].get('status')}, NS: {r['metric'].get('namespace', 'N/A')}, Service: {r['metric'].get('service', r['metric'].get('job', 'N/A'))}")
else:
    print("   ❌ No 4xx error metrics found")

# Check 5xx errors
print("\n3. Checking 5xx errors...")
fivexx = query_prometheus('http_request_duration_seconds_count{status=~"5.."}')
if fivexx.get("data", {}).get("result"):
    print(f"   ✅ Found {len(fivexx['data']['result'])} 5xx error metrics")
    for r in fivexx['data']['result'][:5]:
        print(f"      Status: {r['metric'].get('status')}, NS: {r['metric'].get('namespace', 'N/A')}, Service: {r['metric'].get('service', r['metric'].get('job', 'N/A'))}")
else:
    print("   ❌ No 5xx error metrics found")

# Check error rate
print("\n4. Checking error rate...")
error_rate = query_prometheus('sum(rate(http_request_duration_seconds_count{status=~"[45].."}[5m])) by (status)')
if error_rate.get("data", {}).get("result"):
    print("   ✅ Error Rate by Status:")
    for r in error_rate['data']['result']:
        status = r['metric'].get('status', 'N/A')
        value = float(r['value'][1])
        print(f"      {status}: {value:.6f} req/s")
else:
    print("   ❌ No error rate data found")

# Check targets
print("\n5. Checking Prometheus targets...")
try:
    with urllib.request.urlopen('http://localhost:9090/api/v1/targets', timeout=10) as f:
        targets_data = json.loads(f.read())
        targets = [t for t in targets_data.get('data', {}).get('activeTargets', []) 
                   if ('darey' in str(t).lower() or 'api' in str(t).lower()) and 'prometheus' not in str(t).lower()]
        if targets:
            print(f"   ✅ Found {len(targets)} application targets:")
            for t in targets[:5]:
                print(f"      {t['labels'].get('job', 'N/A')} ({t['labels'].get('namespace', 'N/A')}): {t['health']}")
        else:
            print("   ❌ No application targets found")
except Exception as e:
    print(f"   ❌ Error checking targets: {e}")

print("\n=== SUMMARY ===")
has_errors = (fourxx.get("data", {}).get("result") or fivexx.get("data", {}).get("result"))
if has_errors:
    print("✅ ERROR DATA IS PRESENT IN PROMETHEUS")
    print("   The dashboard should show data if:")
    print("   - Correct namespace is selected")
    print("   - Correct cluster is selected")
    print("   - Dashboard queries match the metric labels")
else:
    print("❌ ERROR DATA NOT FOUND IN PROMETHEUS")
    print("   Reasons:")
    print("   - Applications may not be running")
    print("   - Applications may not be scraped by Prometheus")
    print("   - Applications may be in a different cluster")
    print("   - Error injection may not be reaching the applications")

