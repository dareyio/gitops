#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse
import time

def query_prometheus(query, base="http://localhost:10903"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

def get_alerts(base="http://localhost:10903"):
    try:
        url = f"{base}/api/v1/alerts"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== CHECKING ALERT STATUS ===\n")

# Check if alert is firing
print("1. Checking LabControllerPodDown alert status...")
alert_query = 'ALERTS{alertname="LabControllerPodDown", alertstate="firing"}'
alert_status = query_prometheus(alert_query)

if alert_status.get("data", {}).get("result"):
    print("   ✅ ALERT IS FIRING!")
    for r in alert_status['data']['result']:
        print(f"      Alert: {r['metric'].get('alertname')}")
        print(f"      State: {r['metric'].get('alertstate')}")
        print(f"      Severity: {r['metric'].get('severity')}")
        print(f"      Service: {r['metric'].get('service')}")
        print(f"      Cluster: {r['metric'].get('cluster', 'N/A')}")
else:
    print("   ⏳ Alert not firing yet (may need more time)")

# Check all active alerts
print("\n2. Checking all active alerts...")
all_alerts = get_alerts()
if all_alerts.get("data", {}).get("alerts"):
    lab_alerts = [a for a in all_alerts['data']['alerts'] if 'LabController' in a.get('labels', {}).get('alertname', '')]
    if lab_alerts:
        print(f"   ✅ Found {len(lab_alerts)} LabController alerts:")
        for alert in lab_alerts:
            print(f"      - {alert['labels'].get('alertname')}: {alert.get('state', 'N/A')}")
    else:
        print("   ⏳ No LabController alerts found yet")
else:
    print("   ⏳ No alerts found")

# Check if pods are actually down
print("\n3. Checking if lab-controller pods are down...")
pod_query = 'up{job=~"lab-controller.*", namespace="lab-controller"}'
pod_status = query_prometheus(pod_query)

if pod_status.get("data", {}).get("result"):
    down_pods = [r for r in pod_status['data']['result'] if r['value'][1] == '0']
    if down_pods:
        print(f"   ✅ Found {len(down_pods)} down pods (alert should fire):")
        for r in down_pods:
            print(f"      Pod: {r['metric'].get('pod', 'N/A')}, Cluster: {r['metric'].get('cluster', 'N/A')}")
    else:
        print("   ⚠️  All pods are up (alert won't fire)")
else:
    print("   ⚠️  Could not check pod status")

print("\n=== SUMMARY ===")
if alert_status.get("data", {}).get("result"):
    print("✅ ALERT IS ACTIVE AND FIRING!")
    print("   Check Slack #devops-observability channel for notification")
else:
    print("⏳ Alert not firing yet. It may take up to 2 minutes after pods go down.")

