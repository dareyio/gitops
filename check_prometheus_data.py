#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse
import sys

def check_prometheus(query, name, base_url="http://localhost:9090"):
    try:
        encoded_query = urllib.parse.quote(query, safe='')
        url = f"{base_url}/api/v1/query?query={encoded_query}"
        with urllib.request.urlopen(url, timeout=10) as f:
            data = json.loads(f.read())
            return data
    except Exception as e:
        print(f"❌ Error querying {name}: {e}")
        return None

print("=== CHECKING PROMETHEUS/THANOS FOR ERROR DATA ===\n")

# Check Prometheus
print("1. Checking Prometheus (localhost:9090)...")
prom_4xx = check_prometheus('http_request_duration_seconds_count{status=~"4.."}', "4xx errors")
prom_5xx = check_prometheus('http_request_duration_seconds_count{status=~"5.."}', "5xx errors")
prom_rate = check_prometheus('sum(rate(http_request_duration_seconds_count{status=~"[45].."}[5m])) by (status)', "error rate")
prom_all = check_prometheus('http_request_duration_seconds_count', "all metrics")
try:
    with urllib.request.urlopen('http://localhost:9090/api/v1/targets', timeout=10) as f:
        prom_targets = json.loads(f.read())
except Exception as e:
    print(f"   ❌ Error checking targets: {e}")
    prom_targets = None

if prom_4xx and prom_4xx['data']['result']:
    print(f"   ✅ 4xx Error Metrics: {len(prom_4xx['data']['result'])} found")
    for r in prom_4xx['data']['result'][:5]:
        print(f"      Status: {r['metric'].get('status')}, NS: {r['metric'].get('namespace', 'N/A')}, Service: {r['metric'].get('service', r['metric'].get('job', 'N/A'))}")
else:
    print("   ❌ No 4xx error metrics found")

if prom_5xx and prom_5xx['data']['result']:
    print(f"   ✅ 5xx Error Metrics: {len(prom_5xx['data']['result'])} found")
    for r in prom_5xx['data']['result'][:5]:
        print(f"      Status: {r['metric'].get('status')}, NS: {r['metric'].get('namespace', 'N/A')}, Service: {r['metric'].get('service', r['metric'].get('job', 'N/A'))}")
else:
    print("   ❌ No 5xx error metrics found")

if prom_rate and prom_rate['data']['result']:
    print("   ✅ Error Rate by Status:")
    for r in prom_rate['data']['result']:
        status = r['metric'].get('status', 'N/A')
        value = float(r['value'][1])
        print(f"      {status}: {value:.4f} req/s")
else:
    print("   ❌ No error rate data found")

if prom_all and prom_all['data']['result']:
    namespaces = {}
    error_count = 0
    for r in prom_all['data']['result']:
        ns = r['metric'].get('namespace', 'N/A')
        namespaces[ns] = namespaces.get(ns, 0) + 1
        if r['metric'].get('status', '').startswith(('4', '5')):
            error_count += 1
    print(f"   📊 Total metrics: {len(prom_all['data']['result'])}, Error metrics: {error_count}")
    print("   📊 By Namespace:")
    for ns, count in sorted(namespaces.items())[:10]:
        print(f"      {ns}: {count} metrics")
else:
    print("   ❌ No http_request_duration_seconds_count metrics found at all")

if prom_targets:
    targets = [t for t in prom_targets['data']['activeTargets'] if 'darey' in str(t).lower() or ('api' in str(t).lower() and 'prometheus' not in str(t).lower())]
    if targets:
        print(f"   ✅ Application Targets: {len(targets)} found")
        for t in targets[:5]:
            print(f"      {t['labels'].get('job', 'N/A')} ({t['labels'].get('namespace', 'N/A')}): {t['health']}")
    else:
        print("   ❌ No application targets found")

print("\n2. Checking Thanos Query (localhost:10902)...")
thanos_rate = check_prometheus('sum(rate(http_request_duration_seconds_count{status=~"[45].."}[5m])) by (status)', "error rate", "http://localhost:10902")
thanos_all = check_prometheus('http_request_duration_seconds_count{status=~"[45].."}', "error metrics", "http://localhost:10902")

if thanos_rate and thanos_rate['data']['result']:
    print("   ✅ Thanos Error Rate by Status:")
    for r in thanos_rate['data']['result']:
        status = r['metric'].get('status', 'N/A')
        value = float(r['value'][1])
        print(f"      {status}: {value:.4f} req/s")
else:
    print("   ❌ No error rate data in Thanos")

if thanos_all and thanos_all['data']['result']:
    print(f"   ✅ Thanos Error Metrics: {len(thanos_all['data']['result'])} found")
    for r in thanos_all['data']['result'][:5]:
        print(f"      Status: {r['metric'].get('status')}, NS: {r['metric'].get('namespace', 'N/A')}, Cluster: {r['metric'].get('cluster', 'N/A')}, Service: {r['metric'].get('service', r['metric'].get('job', 'N/A'))}")
else:
    print("   ❌ No error metrics in Thanos")

print("\n=== SUMMARY ===")
if (prom_4xx and prom_4xx['data']['result']) or (prom_5xx and prom_5xx['data']['result']):
    print("✅ Error data IS present in Prometheus")
else:
    print("❌ Error data NOT found in Prometheus")
    print("   Possible reasons:")
    print("   - Applications not running")
    print("   - Applications not being scraped")
    print("   - Metric name is different")
    print("   - Applications in different cluster")

