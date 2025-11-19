# Error Injection Guide for Application Errors Dashboard

This guide helps you inject test errors to populate the Application Errors dashboard.

## Quick Start

### Option 1: Run from a Pod with Network Access

If you have access to a pod that can reach your applications:

```bash
# 1. Find a pod that can access your API
kubectl get pods -A | grep -E "curl|busybox|debug"

# 2. Exec into it (or create a temporary pod)
kubectl run -it --rm error-injector --image=curlimages/curl:latest --restart=Never -- /bin/sh

# 3. Inside the pod, run these commands:
API_URL="http://dareyscore-api.dareyscore.svc:8000"  # Adjust based on your setup

# Generate 404 errors
for i in {1..20}; do
  curl -s -w "\nStatus: %{http_code}\n" "$API_URL/api/v1/nonexistent-$i"
  sleep 0.3
done

# Generate 400 errors (invalid JSON)
for i in {1..10}; do
  curl -s -w "\nStatus: %{http_code}\n" -X POST "$API_URL/api/v1/events" \
    -H "Content-Type: application/json" \
    -d "invalid json {["
  sleep 0.3
done

# Generate 405 errors (method not allowed)
curl -s -w "\nStatus: %{http_code}\n" -X DELETE "$API_URL/api/v1/health"
curl -s -w "\nStatus: %{http_code}\n" -X PATCH "$API_URL/api/v1/health"
```

### Option 2: Use External URL (if available)

If your API is exposed externally:

```bash
API_URL="https://dareyscore.talentos.darey.io"  # Your external URL

# Generate errors
for i in {1..20}; do
  curl -s -w "\nStatus: %{http_code}\n" "$API_URL/api/v1/nonexistent-$i"
  sleep 0.3
done
```

### Option 3: Kubernetes Job (if namespace exists)

```bash
# Update the namespace in inject-errors-job.yaml first
kubectl apply -f inject-errors-job.yaml

# Watch the job
kubectl logs -f job/error-injector -n <namespace>

# Clean up
kubectl delete job error-injector -n <namespace>
```

## What Errors to Generate

### 4xx Errors (Client Errors)
- **404**: Non-existent endpoints
- **400**: Invalid JSON, missing required fields
- **401/403**: Unauthorized requests (if auth is enabled)
- **405**: Method not allowed
- **422**: Unprocessable entity (invalid data format)

### 5xx Errors (Server Errors)
- **500**: Server errors (harder to trigger safely)
- **502**: Bad gateway
- **503**: Service unavailable

## Verify Errors Are Being Captured

1. **Check Prometheus metrics directly:**
   ```bash
   # Port-forward to Prometheus
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   
   # Query in browser: http://localhost:9090
   # Query: http_requests_total{status=~"4.."}
   ```

2. **Check Grafana Explore:**
   - Go to Grafana → Explore
   - Query: `http_requests_total{status=~"4.."}`
   - Should show metrics with status codes 400-499

3. **Check the Dashboard:**
   - Refresh the Application Errors dashboard
   - Select the correct namespace
   - Data should appear within 30-60 seconds

## Troubleshooting

### No Data After Injection

1. **Check if metrics exist:**
   ```bash
   # In Grafana Explore, try:
   http_requests_total
   ```

2. **Check if applications are instrumented:**
   - Verify Prometheus metrics endpoint: `/metrics`
   - Check if ServiceMonitor is configured
   - Verify Prometheus is scraping the pods

3. **Check metric labels:**
   - The metric needs `namespace` and `cluster` labels
   - Verify labels match dashboard filters

### Applications Not Found

If you can't find your applications:
1. Check which cluster you're connected to: `kubectl config current-context`
2. List all namespaces: `kubectl get namespaces`
3. Search for services: `kubectl get svc -A | grep -i api`

## Manual Testing

You can also manually trigger errors by:
1. Making invalid API calls from your application
2. Using Postman/curl with invalid data
3. Hitting endpoints that don't exist
4. Sending malformed requests

## Clean Up

After testing, you can clean up:
```bash
# Delete the job
kubectl delete job error-injector -n <namespace>

# Or delete the temporary pod
kubectl delete pod error-injector
```

