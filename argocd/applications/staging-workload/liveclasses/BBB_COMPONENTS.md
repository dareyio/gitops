# BBB Component Bundle

This document lists ALL BBB-related components that are bundled together for enable/disable operations.

## Component Categories

### Core BBB Services
- `bbb-api-deployment.yaml` - Custom BBB API wrapper (liveclasses-bbb-api)
- `bbb-api-service.yaml` - Service for custom BBB API
- `bbb-native-api-deployment.yaml` - Native BBB API service
- `bbb-web-deployment.yaml` - BBB HTML5 frontend (includes HPA)
- `bbb-web-service.yaml` - Service for BBB web
- `bbb-nginx-deployment.yaml` - Nginx reverse proxy

### Supporting Services
- `bbb-graphql-server-service.yaml` - GraphQL server (placeholder)
- `bbb-graphql-middleware-service.yaml` - GraphQL middleware (placeholder)
- `bbb-etherpad-service.yaml` - Etherpad collaborative editor
- `bbb-greenlight-service.yaml` - Greenlight frontend
- `bbb-redis-service.yaml` - Redis cache
- `bbb-demo-service.yaml` - Demo service (placeholder)

### Media Servers (DaemonSets)
- `freeswitch-daemonset.yaml` - FreeSWITCH for SIP/audio
- `freeswitch-service.yaml` - Service for FreeSWITCH
- `kurento-daemonset.yaml` - Kurento Media Server for WebRTC
- `kurento-service.yaml` - Service for Kurento

### Database (MongoDB)
- `mongodb-statefulset.yaml` - MongoDB replica set (3 replicas)
- `mongodb-service.yaml` - Headless service for MongoDB
- `mongodb-configmap.yaml` - MongoDB configuration
- `mongodb-secret.yaml` - MongoDB credentials secret
- `mongodb-keyfile-secret.yaml` - MongoDB keyfile for replica set
- `mongodb-pdb.yaml` - Pod Disruption Budget
- `mongodb-init-job.yaml` - Replica set initialization job
- `mongodb-backup-cronjob.yaml` - Daily backup cronjob
- `mongodb-backup-serviceaccount.yaml` - Service account for backups
- `mongodb-restore-job.yaml` - Restore job template

### Configuration
- `bbb-bigbluebutton-configmap.yaml` - BBB Nginx configuration
- `bbb-html5-nginx-configmap.yaml` - HTML5 client Nginx config
- `bbb-config-secret.yaml` - BBB configuration secret

### Secrets (ExternalSecrets)
- `bbb-secret-externalsecret.yaml` - BBB API secret
- `mongodb-secret-externalsecret.yaml` - MongoDB credentials
- `mongodb-keyfile-externalsecret.yaml` - MongoDB keyfile

## Resources Created Automatically

### HPAs (HorizontalPodAutoscalers)
- `bbb-web-hpa` - Defined inline in `bbb-web-deployment.yaml` (automatically included)
- `liveclasses-bbb-api-hpa` - Defined inline in `bbb-api-deployment.yaml` (automatically included)
- `bbb-nginx-hpa` - Defined inline in `bbb-nginx-deployment.yaml` (automatically included)

### PVCs (PersistentVolumeClaims)
- `mongodb-data-mongodb-0` - Created automatically by StatefulSet
- `mongodb-data-mongodb-1` - Created automatically by StatefulSet
- `mongodb-data-mongodb-2` - Created automatically by StatefulSet

## How to Enable/Disable BBB

### Enable BBB
1. Update `liveclasses-config.yaml`:
   ```yaml
   provider: "bbb"
   bbb_enabled: "true"
   jitsi_enabled: "false"
   ```

2. Update `kustomization.yaml`:
   ```yaml
   resources:
     - namespace.yaml
     - liveclasses-config.yaml
     - liveclasses-recordings-serviceaccount.yaml
     - liveclasses-streaming-ingress.yaml
     - bbb  # Add this line
     # Jitsi resources...
   ```

3. Commit and push - ArgoCD will sync automatically

### Disable BBB
1. Update `liveclasses-config.yaml`:
   ```yaml
   provider: "jitsi"
   bbb_enabled: "false"
   jitsi_enabled: "true"
   ```

2. Update `kustomization.yaml`:
   ```yaml
   resources:
     - namespace.yaml
     - liveclasses-config.yaml
     - liveclasses-recordings-serviceaccount.yaml
     - liveclasses-streaming-ingress.yaml
     # - bbb  # Remove or comment out this line
     # Jitsi resources...
   ```

3. Commit and push - ArgoCD will prune all BBB resources automatically

## Verification

After enabling/disabling, verify all components:

```bash
# Check BBB deployments
kubectl get deployments -n liveclasses | grep -E "bbb|mongodb|freeswitch|kurento|etherpad|greenlight|redis"

# Check BBB daemonsets
kubectl get daemonsets -n liveclasses | grep -E "freeswitch|kurento"

# Check BBB statefulsets
kubectl get statefulsets -n liveclasses | grep -E "mongodb"

# Check BBB services
kubectl get services -n liveclasses | grep -E "bbb|mongodb|freeswitch|kurento|etherpad|greenlight|redis"

# Check BBB configmaps
kubectl get configmaps -n liveclasses | grep -E "bbb|mongodb"

# Check BBB secrets
kubectl get secrets -n liveclasses | grep -E "bbb|mongodb"

# Check BBB external secrets
kubectl get externalsecrets -n liveclasses | grep -E "bbb|mongodb"

# Check BBB HPAs
kubectl get hpa -n liveclasses | grep -E "bbb"

# Check BBB PVCs
kubectl get pvc -n liveclasses | grep -E "mongodb"
```

## Notes

- **TURN Server**: `coturn` and `turn-credentials-api` are NOT included in the BBB bundle as they may be shared with Jitsi
- **Ingress Routes**: BBB ingress routes are defined in `liveclasses-streaming-ingress.yaml` and should be updated when switching providers
- **PVCs**: MongoDB PVCs are NOT automatically deleted when BBB is disabled (data preservation). Manually delete if needed:
  ```bash
  kubectl delete pvc -n liveclasses -l app=mongodb
  ```

