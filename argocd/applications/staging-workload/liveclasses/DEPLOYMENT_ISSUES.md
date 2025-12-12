# Staging BBB Stack Deployment Issues

## ✅ What's Deployed

All resources have been created:
- ✅ MongoDB StatefulSet (0/3 ready - waiting for secrets)
- ✅ BBB Web Deployment (0/2 ready - ImagePullBackOff)
- ✅ BBB Native API Deployment (0/2 ready - ImagePullBackOff)
- ✅ FreeSWITCH DaemonSet (0/6 ready - Pending)
- ✅ Kurento DaemonSet (0/6 ready - Pending)

## ❌ Blocking Issues

### 1. BBB Images Not in ECR
**Error**: `ImagePullBackOff` for:
- `586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-web:3.0.4`
- `586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-html5:3.0.4`
- `586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/freeswitch:3.0.4`
- `586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/kurento-media-server:3.0.4`

**Solution**: Run the image sync script:
```bash
cd /Users/dare/Desktop/xterns/darey-new
./scripts/sync-bbb-images-to-ecr.sh
```

### 2. MongoDB Secrets Missing
**Error**: MongoDB pods are `Pending` - waiting for secrets

**Required Secrets**:
- `mongodb-secret` (from ExternalSecret: `staging/liveclasses/mongodb`)
- `mongodb-keyfile` (from ExternalSecret: `staging/liveclasses/mongodb-keyfile`)

**Solution**: Run Terraform to create secrets:
```bash
cd /Users/dare/Desktop/xterns/darey-new/terraform
./docker-run.sh staging apply -auto-approve
```

### 3. ExternalSecrets Not Synced
**Status**: ExternalSecrets exist but secrets may not be synced yet

**Check**:
```bash
kubectl get externalsecret -n liveclasses
kubectl get secret mongodb-secret mongodb-keyfile -n liveclasses
```

## 🔄 Next Steps

1. **Sync BBB Images to ECR** (if not done)
2. **Run Terraform** to create MongoDB secrets
3. **Wait for ExternalSecrets** to sync
4. **MongoDB pods** should start after secrets are available
5. **BBB pods** should start after images are in ECR

## 📊 Current Status

```bash
# Check deployments
kubectl get deployment,statefulset,daemonset -n liveclasses

# Check pods
kubectl get pods -n liveclasses

# Check image pull errors
kubectl describe pod <pod-name> -n liveclasses | grep -A 5 "Events:"
```

