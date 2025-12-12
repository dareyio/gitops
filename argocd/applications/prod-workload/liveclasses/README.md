# Liveclasses Application

This directory contains Kubernetes manifests for the liveclasses application, supporting both Jitsi and BigBlueButton (BBB) for live streaming.

## Architecture

- **Path-based routing**: `/jitsi/*` → Jitsi, `/bbb/*` → BBB, `/` → based on ConfigMap (default: BBB)
- **Feature flag**: ConfigMap controls which provider is enabled
- **Shared S3 bucket**: Both providers use the same bucket with organized folder structure
- **Hybrid deployment**: Stateless Deployments for web/api, DaemonSets for media processing

## Components

### BBB Components (Always Deployed)
- `bbb-web` - BBB HTML5 frontend
- `bbb-api` - BBB API service (native)
- `liveclasses-bbb-api` - Custom BBB API service (meetings, recordings, webhooks)
- `bbb-nginx` - Nginx reverse proxy
- `freeswitch` - DaemonSet for SIP/audio processing
- `kurento-media-server` - DaemonSet for WebRTC media processing

### Jitsi Components (Conditionally Deployed)
- `jitsi-web` - Jitsi Meet frontend
- `jicofo` - Jitsi Conference Focus
- `jvb` - Jitsi Video Bridge
- `prosody` - XMPP server
- `jibri` - Recording service

## Configuration

### ConfigMap: `liveclasses-config`

Key settings:
- `provider`: "bbb" or "jitsi" (default provider)
- `jitsi_enabled`: "true" or "false"
- `bbb_enabled`: "true" or "false"
- `s3_bucket_name`: S3 bucket for recordings
- `environment`: "prod" or "staging"

## Managing Jitsi Deployments

Use the `manage-jitsi.sh` script to enable/disable Jitsi deployments:

```bash
# Check current status
./manage-jitsi.sh check

# Disable Jitsi (scale down to 0 replicas)
./manage-jitsi.sh disable

# Enable Jitsi (scale up to original replicas)
./manage-jitsi.sh enable

# Sync with ConfigMap value
./manage-jitsi.sh sync
```

This script:
- Scales Jitsi deployments to 0 when disabled (frees resources)
- Scales back up when enabled
- Updates the ConfigMap accordingly

## Resource Management

### When Jitsi is Disabled
Jitsi deployments consume significant resources:
- `jitsi-web`: 500m CPU, 512Mi memory
- `jicofo`: 500m CPU, 512Mi memory
- `jvb`: 1000m CPU, 2Gi memory (largest)
- `prosody`: 300m CPU, 512Mi memory
- `jibri`: 1500m CPU, 3Gi memory (very large)

**Total when enabled**: ~3.8 CPU, ~6.5Gi memory

Disabling Jitsi frees these resources for BBB and other workloads.

### BBB API Service
Resource requests reduced for testing:
- Requests: 100m CPU, 128Mi memory
- Limits: 1000m CPU, 1Gi memory

## Deployment

### Using Kustomize (Recommended)

```bash
# Deploy with Jitsi enabled
kubectl apply -k overlays/jitsi-enabled

# Deploy with Jitsi disabled
kubectl apply -k overlays/jitsi-disabled
```

### Manual Deployment

```bash
# Apply base resources (BBB + shared)
kubectl apply -f base/

# Apply Jitsi if enabled
if [ "$(kubectl get configmap liveclasses-config -n liveclasses -o jsonpath='{.data.jitsi_enabled}')" = "true" ]; then
  kubectl apply -f jitsi-web-deployment.yaml
  kubectl apply -f jicofo-deployment.yaml
  kubectl apply -f jvb-deployment.yaml
  kubectl apply -f prosody-deployment.yaml
  kubectl apply -f jibri-deployment.yaml
fi
```

## Testing

### Health Check
```bash
# BBB API service
kubectl port-forward -n liveclasses svc/liveclasses-bbb-api 8080:8080
curl http://localhost:8080/health
```

### End-to-End Testing
1. Create a BBB meeting via API
2. Generate join URL
3. Join meeting in browser
4. Test recording functionality
5. Verify S3 upload structure

## Troubleshooting

### Pods Not Scheduling
- Check resource constraints: `kubectl top nodes`
- Disable Jitsi if not needed: `./manage-jitsi.sh disable`
- Reduce resource requests temporarily

### BBB API Not Responding
- Check pod logs: `kubectl logs -n liveclasses -l app=liveclasses-bbb-api`
- Verify secrets are configured
- Check service: `kubectl get svc -n liveclasses liveclasses-bbb-api`

### Jitsi Not Working
- Verify Jitsi is enabled: `kubectl get configmap liveclasses-config -n liveclasses -o yaml`
- Check deployments: `kubectl get deployments -n liveclasses | grep jitsi`
- Scale up if needed: `./manage-jitsi.sh enable`

