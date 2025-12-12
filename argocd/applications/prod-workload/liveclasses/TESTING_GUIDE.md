# Liveclasses End-to-End Testing Guide

## Prerequisites

1. BBB API service deployed and running
2. Jitsi disabled (to free resources): `./manage-jitsi.sh disable`
3. ConfigMap configured with correct values
4. Secrets configured (bbb-secrets, supabase-secrets)

## Testing Steps

### 1. Verify BBB API Service is Running

```bash
# Check pod status
kubectl get pods -n liveclasses -l app=liveclasses-bbb-api

# Check service
kubectl get svc -n liveclasses liveclasses-bbb-api

# Check logs
kubectl logs -n liveclasses -l app=liveclasses-bbb-api --tail=50
```

Expected: Pods should be in `Running` state, service should have ClusterIP assigned.

### 2. Test Health Endpoint

```bash
# Via port-forward
kubectl port-forward -n liveclasses svc/liveclasses-bbb-api 8080:8080
curl http://localhost:8080/health

# Via test pod
kubectl run -n liveclasses --rm -i --restart=Never test-api --image=curlimages/curl -- \
  curl -s http://liveclasses-bbb-api:8080/health
```

Expected response:
```json
{
  "status": "healthy",
  "service": "liveclasses-bbb-api",
  "timestamp": "2025-12-12T..."
}
```

### 3. Test Meeting Creation

```bash
# Create a test meeting
curl -X POST http://localhost:8080/api/v1/meetings/create \
  -H "Content-Type: application/json" \
  -d '{
    "meetingID": "test-meeting-123",
    "name": "Test Meeting",
    "record": true
  }'
```

Note: This will fail if BBB API (native) is not accessible, but tests our endpoint structure.

### 4. Test Recordings Endpoint

```bash
# List recordings
curl http://localhost:8080/api/v1/recordings

# Should return empty array or existing recordings
```

### 5. Test via Ingress (Once Ingress is Updated)

```bash
# Test health via ingress
curl https://streaming.talentos.darey.io/api/v1/health

# Test BBB path
curl https://streaming.talentos.darey.io/bbb/
```

### 6. Test Jitsi Management Script

```bash
cd gitops/argocd/applications/prod-workload/liveclasses

# Check current status
./manage-jitsi.sh check

# Disable Jitsi (frees ~3.8 CPU, ~6.5Gi memory)
./manage-jitsi.sh disable

# Verify Jitsi pods are scaled down
kubectl get pods -n liveclasses | grep -E "jitsi|jibri|jicofo|jvb|prosody"

# Re-enable if needed
./manage-jitsi.sh enable
```

### 7. Resource Monitoring

```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n liveclasses

# Check if BBB API pods can schedule now
kubectl get pods -n liveclasses -l app=liveclasses-bbb-api -o wide
```

## Troubleshooting

### Pods Not Starting

1. **Check resource constraints:**
   ```bash
   kubectl describe pod -n liveclasses <pod-name> | grep -A 10 "Events"
   ```

2. **Disable Jitsi to free resources:**
   ```bash
   ./manage-jitsi.sh disable
   ```

3. **Reduce resource requests temporarily:**
   ```bash
   kubectl patch deployment liveclasses-bbb-api -n liveclasses -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","resources":{"requests":{"cpu":"50m","memory":"64Mi"}}}]}}}}'
   ```

### API Not Responding

1. **Check pod logs:**
   ```bash
   kubectl logs -n liveclasses -l app=liveclasses-bbb-api --tail=100
   ```

2. **Check if secrets are configured:**
   ```bash
   kubectl get secrets -n liveclasses bbb-secrets supabase-secrets
   ```

3. **Verify ConfigMap:**
   ```bash
   kubectl get configmap liveclasses-config -n liveclasses -o yaml
   ```

### Architecture Mismatch

If you see "exec format error":
- Rebuild image for linux/amd64: `docker build --platform linux/amd64 ...`
- Push to ECR
- Restart deployment: `kubectl rollout restart deployment liveclasses-bbb-api -n liveclasses`

## Success Criteria

- ✅ BBB API pods are running
- ✅ Health endpoint returns 200 OK
- ✅ Service is accessible via ClusterIP
- ✅ Jitsi can be disabled/enabled via script
- ✅ Resources are freed when Jitsi is disabled
- ✅ Ingress routes correctly to BBB

## Next Steps After Testing

1. Configure real BBB API secret
2. Configure real Supabase credentials
3. Deploy BBB native components (web, api, freeswitch, kurento)
4. Test full meeting creation and join flow
5. Test recording functionality
6. Verify S3 upload structure

