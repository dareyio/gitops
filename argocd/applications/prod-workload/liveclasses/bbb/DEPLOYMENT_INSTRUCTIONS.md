# BBB Infrastructure Deployment Instructions (GitOps)

## Overview

All infrastructure is managed through GitOps (ArgoCD). Changes are committed to the gitops repository and ArgoCD automatically syncs them to the cluster.

## Prerequisites

1. Terraform applied for production (S3 bucket and IAM role created)
2. Service account annotation updated (via GitOps)
3. BBB images synced to ECR
4. Secrets configured (via External Secrets Operator or manual secrets)

## GitOps Workflow

All deployments go through GitOps:
1. **Commit changes** to gitops repository
2. **Push to main branch** (or create PR)
3. **ArgoCD automatically syncs** (if auto-sync enabled)
4. **Or manually sync** via ArgoCD UI/CLI

## Deployment Steps

### Step 1: Generate MongoDB Keyfile Secret

**Option A: Using External Secrets Operator (Recommended)**

Create an ExternalSecret in AWS Secrets Manager and sync it:

```yaml
# File: argocd/applications/prod-workload/liveclasses/bbb/mongodb-keyfile-externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mongodb-keyfile
  namespace: liveclasses
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: mongodb-keyfile
    creationPolicy: Owner
  data:
    - secretKey: keyfile
      remoteRef:
        key: prod/liveclasses/mongodb-keyfile
```

Generate the keyfile value:
```bash
openssl rand -base64 756
```

Store in AWS Secrets Manager as `prod/liveclasses/mongodb-keyfile`

**Option B: Manual Secret (Temporary)**

If not using External Secrets, update `mongodb-keyfile-secret.yaml` with the generated keyfile and commit.

### Step 2: Configure Secrets

**Update these files with production values or use External Secrets:**

1. **mongodb-secret.yaml** - MongoDB credentials
   - Root username/password
   - Database user credentials
   - Or create ExternalSecret to sync from AWS Secrets Manager

2. **bbb-config-secret.yaml** - BBB API secret
   - Generate secure salt: `openssl rand -base64 32`
   - Or create ExternalSecret to sync from AWS Secrets Manager

### Step 3: Sync BBB Images to ECR

```bash
cd /Users/dare/Desktop/xterns/darey-new
./scripts/sync-bbb-images-to-ecr.sh
```

This pulls BBB images from Docker Hub and pushes them to ECR. The deployment manifests already reference ECR images.

### Step 4: Commit and Push to GitOps

```bash
cd /Users/dare/Desktop/xterns/darey-new/gitops

# Review changes
git status

# Add all new files
git add argocd/applications/prod-workload/liveclasses/

# Commit
git commit -m "feat: Add MongoDB HA and BBB native components"

# Push to main (or create PR)
git push origin main
```

### Step 5: ArgoCD Sync

**If auto-sync is enabled** (which it is for liveclasses), ArgoCD will automatically sync within a few minutes.

**To manually trigger sync:**

```bash
# Via ArgoCD CLI
argocd app sync liveclasses

# Or via ArgoCD UI
# Navigate to Applications > liveclasses > Sync
```

### Step 6: Initialize MongoDB Replica Set

After MongoDB StatefulSet pods are running, initialize the replica set:

**Option A: One-time Job (GitOps)**

The `mongodb-init-job.yaml` is included in the base kustomization. However, since it's a one-time job, you may want to apply it manually after the first sync:

```bash
# Wait for MongoDB pods to be ready
kubectl wait --for=condition=ready pod -l app=mongodb -n liveclasses --timeout=300s

# Apply init job (one-time)
kubectl apply -f argocd/applications/prod-workload/liveclasses/bbb/mongodb-init-job.yaml

# Check status
kubectl get job mongodb-init-replicaset -n liveclasses
kubectl logs job/mongodb-init-replicaset -n liveclasses
```

**Option B: Add to GitOps (if you want it managed)**

If you want the init job managed by GitOps, add it to `base/kustomization.yaml` and it will be created. Note: Jobs can only run once, so you may need to delete and recreate if it fails.

### Step 7: Verify Deployment

```bash
# Check ArgoCD application status
argocd app get liveclasses

# Check all pods
kubectl get pods -n liveclasses

# Check MongoDB replica set (after init)
kubectl exec -it mongodb-0 -n liveclasses -- mongosh \
  --username="mongodb-admin" \
  --password="YOUR_PASSWORD" \
  --authenticationDatabase=admin \
  --eval "rs.status()"

# Test BBB API
kubectl port-forward -n liveclasses svc/bbb-api 8090:8090
curl http://localhost:8090/bigbluebutton/api

# Test custom BBB API
kubectl port-forward -n liveclasses svc/liveclasses-bbb-api 8080:8080
curl http://localhost:8080/health
```

## Restore from Backup

To restore MongoDB from a backup, create a restore job:

**Option A: Manual Job (One-time)**

```bash
# Edit mongodb-restore-job.yaml with RESTORE_DATE and RESTORE_TIME
# Then apply manually
kubectl apply -f argocd/applications/prod-workload/liveclasses/bbb/mongodb-restore-job.yaml

# Monitor
kubectl logs job/mongodb-restore -n liveclasses -f
```

**Option B: Add to GitOps**

If you want restore jobs managed by GitOps, you can add the restore job to kustomization, but remember to remove it after restore completes.

## Monitoring ArgoCD Sync

```bash
# Watch ArgoCD sync status
argocd app get liveclasses --refresh

# View sync history
argocd app history liveclasses

# View application resources
argocd app resources liveclasses
```

## Troubleshooting

### ArgoCD Not Syncing

```bash
# Check application status
argocd app get liveclasses

# Check for sync errors
argocd app get liveclasses | grep -A 10 "Status"

# Force refresh
argocd app get liveclasses --refresh
```

### MongoDB Replica Set Not Initialized

The init job may need to be run manually after first deployment. See Step 6.

### Secrets Not Syncing

If using External Secrets Operator:
```bash
# Check ExternalSecret status
kubectl get externalsecret -n liveclasses

# Check SecretStore
kubectl get secretstore -n liveclasses

# View ExternalSecret events
kubectl describe externalsecret mongodb-secret -n liveclasses
```

## Troubleshooting

### ArgoCD Sync Issues

```bash
# Check application sync status
argocd app get liveclasses

# View sync operation details
argocd app get liveclasses --refresh

# Check for resource conflicts
argocd app resources liveclasses
```

### MongoDB Replica Set Not Initialized

```bash
# Check init job logs
kubectl logs job/mongodb-init-replicaset -n liveclasses

# Manually initialize if needed (one-time)
kubectl exec -it mongodb-0 -n liveclasses -- mongosh \
  --username="mongodb-admin" \
  --password="YOUR_PASSWORD" \
  --authenticationDatabase=admin \
  --eval "rs.initiate()"
```

### MongoDB Pods Not Starting

```bash
# Check pod events
kubectl describe pod mongodb-0 -n liveclasses

# Check logs
kubectl logs mongodb-0 -n liveclasses

# Verify PVCs
kubectl get pvc -n liveclasses

# Check ArgoCD sync status for these resources
argocd app resources liveclasses | grep mongodb
```

### BBB API Cannot Connect to MongoDB

```bash
# Test MongoDB connectivity from BBB API pod
kubectl exec -it <bbb-api-pod> -n liveclasses -- \
  mongosh "mongodb://mongodb-0.mongodb.liveclasses.svc.cluster.local:27017/bigbluebutton?replicaSet=bbb-rs" \
  --username="bbb" \
  --password="YOUR_PASSWORD"
```

### Secrets Not Syncing (External Secrets)

```bash
# Check ExternalSecret status
kubectl get externalsecret -n liveclasses

# View ExternalSecret details
kubectl describe externalsecret mongodb-secret -n liveclasses

# Check SecretStore
kubectl get secretstore -n liveclasses
```

## Monitoring

- **ArgoCD**: Application sync status and health
- **MongoDB metrics**: Available via Prometheus (if ServiceMonitor created)
- **Backup status**: Check CronJob logs via `kubectl logs cronjob/mongodb-backup`
- **Replica set health**: `rs.status()` command

## Maintenance

- **Daily**: Review backup job logs
- **Weekly**: Verify replica set health and ArgoCD sync status
- **Monthly**: Test restore procedure
- **Quarterly**: Review and update MongoDB version

## GitOps Best Practices

1. **Never use kubectl apply** - All changes go through GitOps
2. **Review changes** before committing to main branch
3. **Use PRs** for production changes when possible
4. **Monitor ArgoCD** sync status after pushing changes
5. **Use External Secrets** for sensitive data instead of committing secrets
6. **Test in staging** first if available

