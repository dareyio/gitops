#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse

def query_prometheus(query, base="http://localhost:9095"):
    try:
        encoded = urllib.parse.quote(query, safe='')
        url = f"{base}/api/v1/query?query={encoded}"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

def get_alerts(base="http://localhost:9095"):
    try:
        url = f"{base}/api/v1/alerts"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

def get_rules(base="http://localhost:9095"):
    try:
        url = f"{base}/api/v1/rules"
        with urllib.request.urlopen(url, timeout=10) as f:
            return json.loads(f.read())
    except Exception as e:
        return {"error": str(e)}

print("=== CHECKING PROMETHEUS ALERTS ===\n")

# Check all alerts
print("1. Checking all alerts in Prometheus...")
all_alerts = get_alerts()
if all_alerts.get("data", {}).get("alerts"):
    print(f"   ✅ Found {len(all_alerts['data']['alerts'])} total alerts")
    
    # Filter for our application alerts
    app_alerts = [a for a in all_alerts['data']['alerts'] 
                  if any(x in a.get('labels', {}).get('alertname', '') 
                        for x in ['LabController', 'DareyScore', 'LiveClasses'])]
    
    if app_alerts:
        print(f"\n   ✅ Found {len(app_alerts)} application alerts:")
        for alert in app_alerts:
            name = alert['labels'].get('alertname', 'N/A')
            state = alert.get('state', 'N/A')
            severity = alert['labels'].get('severity', 'N/A')
            active = alert.get('activeAt', 'N/A')
            print(f"\n      Alert: {name}")
            print(f"      State: {state}")
            print(f"      Severity: {severity}")
            print(f"      Active Since: {active}")
            if 'annotations' in alert:
                print(f"      Summary: {alert['annotations'].get('summary', 'N/A')}")
    else:
        print("   ⚠️  No application alerts found")
    
    # Show all firing alerts
    firing = [a for a in all_alerts['data']['alerts'] if a.get('state') == 'firing']
    if firing:
        print(f"\n   🔥 Found {len(firing)} FIRING alerts:")
        for alert in firing[:10]:
            print(f"      - {alert['labels'].get('alertname')} ({alert['labels'].get('severity', 'N/A')})")
    else:
        print("\n   ⏳ No firing alerts found")
else:
    print("   ⚠️  Could not retrieve alerts or no alerts found")

# Check alert rules
print("\n2. Checking alert rules...")
rules = get_rules()
if rules.get("data", {}).get("groups"):
    app_rules = []
    for group in rules['data']['groups']:
        for rule in group.get('rules', []):
            if rule.get('type') == 'alerting':
                name = rule.get('name', 'N/A')
                if any(x in name for x in ['LabController', 'DareyScore', 'LiveClasses']):
                    app_rules.append({
                        'name': name,
                        'state': rule.get('state', 'N/A'),
                        'health': rule.get('health', 'N/A'),
                        'query': rule.get('query', 'N/A')[:100] + '...' if len(rule.get('query', '')) > 100 else rule.get('query', 'N/A')
                    })
    
    if app_rules:
        print(f"   ✅ Found {len(app_rules)} application alert rules:")
        for rule in app_rules:
            print(f"\n      Rule: {rule['name']}")
            print(f"      State: {rule['state']}")
            print(f"      Health: {rule['health']}")
            print(f"      Query: {rule['query']}")
    else:
        print("   ⚠️  No application alert rules found")
else:
    print("   ⚠️  Could not retrieve rules")

# Check specific alert
print("\n3. Checking LabControllerPodDown alert specifically...")
lab_alert = query_prometheus('ALERTS{alertname="LabControllerPodDown"}')
if lab_alert.get("data", {}).get("result"):
    print("   ✅ LabControllerPodDown alert exists:")
    for r in lab_alert['data']['result']:
        state = r['metric'].get('alertstate', 'N/A')
        print(f"      State: {state}")
        print(f"      Labels: {r['metric']}")
else:
    print("   ⚠️  LabControllerPodDown alert not found in ALERTS metric")

# Check if the rule is loaded
print("\n4. Checking if deployment metric exists...")
deploy_metric = query_prometheus('kube_deployment_status_replicas_available{namespace="lab-controller", deployment="lab-controller"}')
if deploy_metric.get("data", {}).get("result"):
    print("   ✅ Deployment metric exists:")
    for r in deploy_metric['data']['result']:
        value = r['value'][1]
        cluster = r['metric'].get('cluster', 'N/A')
        print(f"      Cluster: {cluster}, Available Replicas: {value}")
else:
    print("   ⚠️  Deployment metric not found")
    print("   This could mean:")
    print("   - kube-state-metrics is not running")
    print("   - Metrics not being scraped")
    print("   - Wrong namespace/deployment name")

print("\n=== SUMMARY ===")
if all_alerts.get("data", {}).get("alerts"):
    firing_count = len([a for a in all_alerts['data']['alerts'] if a.get('state') == 'firing'])
    if firing_count > 0:
        print(f"✅ Prometheus has {firing_count} firing alerts")
    else:
        print("⏳ No alerts are currently firing")
        print("   This is normal if all systems are healthy")
else:
    print("⚠️  Could not retrieve alerts from Prometheus")

