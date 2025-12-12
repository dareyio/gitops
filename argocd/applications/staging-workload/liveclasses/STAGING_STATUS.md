# Staging Liveclasses Status

## Current State (as of check)

### ✅ What's Working:
1. **BBB API Service**: 2/2 pods running and healthy
   - Endpoint: `http://liveclasses-bbb-api:8080`
   - Health checks: Passing
   - Logs: Normal operation

2. **Ingress (Partial)**:
   - `jitsi-streaming-ingress`: Routes to Jitsi only (`streaming-stg.talentos.darey.io`)
   - `liveclasses-streaming-ingress`: Routes to production domain (`streaming.talentos.darey.io`) - **WRONG CLUSTER**

### ❌ What's Missing:
1. **MongoDB**: Not deployed (no StatefulSet)
   - Required for BBB native API
   - Required for meeting metadata storage

2. **BBB Web Frontend**: Not deployed
   - Ingress shows: `error: endpoints "bbb-web" not found`
   - Required for user interface

3. **BBB Native API**: Not deployed
   - Required for BBB core functionality

4. **FreeSWITCH DaemonSet**: Not deployed
   - Required for audio/video processing

5. **Kurento Media Server DaemonSet**: Not deployed
   - Required for WebRTC media processing

6. **Staging Ingress**: Missing BBB routes
   - Current ingress only routes to Jitsi
   - Needs `/bbb` and `/bbb/api` paths

7. **Staging ConfigMap**: Not configured
   - No `liveclasses-config` ConfigMap in staging
   - Needs staging-specific values

## Test Endpoints

### Current (Not Working):
- ❌ `https://streaming-stg.talentos.darey.io/bbb/api/health` - Returns HTML (Jitsi page)
- ❌ `https://streaming.talentos.darey.io/bbb/api/health` - 503 Service Unavailable

### Expected (After Setup):
- ✅ `https://streaming-stg.talentos.darey.io/bbb/api/health` - Should return JSON health status
- ✅ `https://streaming-stg.talentos.darey.io/bbb/api/meetings` - BBB API endpoints
- ✅ `https://streaming-stg.talentos.darey.io/bbb` - BBB web interface

## Next Steps

1. **Create staging ConfigMap** with staging-specific values
2. **Update staging ingress** to include BBB routes
3. **Deploy MongoDB** StatefulSet (3 replicas)
4. **Deploy BBB components**:
   - BBB Web frontend
   - BBB Native API
   - FreeSWITCH DaemonSet
   - Kurento DaemonSet
5. **Create ExternalSecrets** for staging secrets
6. **Update Terraform** to create staging secrets in AWS Secrets Manager

## Deployment Order

1. Terraform: Create staging secrets
2. GitOps: Deploy MongoDB
3. GitOps: Deploy BBB components
4. GitOps: Update ingress
5. Test endpoints

