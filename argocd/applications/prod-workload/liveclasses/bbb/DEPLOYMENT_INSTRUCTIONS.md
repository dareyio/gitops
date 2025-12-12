# BBB Infrastructure Deployment Instructions

## Prerequisites

1. Terraform applied for production (S3 bucket and IAM role created)
2. Service account annotation updated
3. BBB images synced to ECR

## Deployment Order

### Step 1: Generate MongoDB Keyfile

```bash
# Generate secure keyfile for MongoDB replica set
openssl rand -base64 756 > /tmp/mongodb-keyfile

# Create secret from keyfile
kubectl create secret generic mongodb-keyfile \
  --from-file=keyfile=/tmp/mongodb-keyfile \
  -n liveclasses

# Clean up
rm /tmp/mongodb-keyfile
```

### Step 2: Update MongoDB Secrets

**Important:** Update secrets with production values before deploying:

```bash
# Update mongodb-secret with real credentials
kubectl edit secret mongodb-secret -n liveclasses

# Or use External Secrets Operator to sync from AWS Secrets Manager
```

### Step 3: Deploy MongoDB

```bash
# Apply MongoDB resources in order
kubectl apply -f mongodb-configmap.yaml
kubectl apply -f mongodb-secret.yaml
kubectl apply -f mongodb-keyfile-secret.yaml
kubectl apply -f mongodb-service.yaml
kubectl apply -f mongodb-statefulset.yaml
kubectl apply -f mongodb-pdb.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app=mongodb -n liveclasses --timeout=300s
```

### Step 4: Initialize MongoDB Replica Set

```bash
# Run init job
kubectl apply -f mongodb-init-job.yaml

# Check job status
kubectl get job mongodb-init-replicaset -n liveclasses

# View logs
kubectl logs job/mongodb-init-replicaset -n liveclasses

# Verify replica set status
kubectl exec -it mongodb-0 -n liveclasses -- mongosh \
  --username="mongodb-admin" \
  --password="YOUR_PASSWORD" \
  --authenticationDatabase=admin \
  --eval "rs.status()"
```

### Step 5: Deploy MongoDB Backup

```bash
# Apply backup service account
kubectl apply -f mongodb-backup-serviceaccount.yaml

# Apply backup CronJob
kubectl apply -f mongodb-backup-cronjob.yaml

# Verify CronJob
kubectl get cronjob mongodb-backup -n liveclasses
```

### Step 6: Sync BBB Images to ECR

```bash
# Run image sync script
cd /Users/dare/Desktop/xterns/darey-new
./scripts/sync-bbb-images-to-ecr.sh
```

### Step 7: Update BBB Secrets

```bash
# Update bbb-secrets with real API secret
kubectl edit secret bbb-secrets -n liveclasses

# Or use External Secrets Operator
```

### Step 8: Deploy BBB Native Components

```bash
# Apply BBB native API
kubectl apply -f bbb-native-api-deployment.yaml
kubectl apply -f bbb-api-service.yaml

# Apply BBB web
kubectl apply -f bbb-web-deployment.yaml
kubectl apply -f bbb-web-service.yaml

# Apply BBB nginx
kubectl apply -f bbb-nginx-deployment.yaml

# Apply FreeSWITCH and Kurento (already using ECR images)
kubectl apply -f freeswitch-daemonset.yaml
kubectl apply -f kurento-daemonset.yaml
```

### Step 9: Verify Deployment

```bash
# Check all pods
kubectl get pods -n liveclasses

# Check MongoDB replica set
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

To restore MongoDB from a backup:

```bash
# Edit restore job with backup date and time
kubectl create job mongodb-restore-manual \
  --from=cronjob/mongodb-backup \
  -n liveclasses

# Edit the job to set RESTORE_DATE and RESTORE_TIME
kubectl edit job mongodb-restore-manual -n liveclasses

# Set environment variables:
# RESTORE_DATE=2025-12-12
# RESTORE_TIME=020000

# Apply and monitor
kubectl apply -f mongodb-restore-job.yaml
kubectl logs job/mongodb-restore -n liveclasses -f
```

## Troubleshooting

### MongoDB Replica Set Not Initialized

```bash
# Check init job logs
kubectl logs job/mongodb-init-replicaset -n liveclasses

# Manually initialize if needed
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
```

### BBB API Cannot Connect to MongoDB

```bash
# Test MongoDB connectivity from BBB API pod
kubectl exec -it <bbb-api-pod> -n liveclasses -- \
  mongosh "mongodb://mongodb-0.mongodb.liveclasses.svc.cluster.local:27017/bigbluebutton?replicaSet=bbb-rs" \
  --username="bbb" \
  --password="YOUR_PASSWORD"
```

## Monitoring

- MongoDB metrics: Available via Prometheus (if ServiceMonitor created)
- Backup status: Check CronJob logs
- Replica set health: `rs.status()` command

## Maintenance

- **Daily**: Review backup job logs
- **Weekly**: Verify replica set health
- **Monthly**: Test restore procedure
- **Quarterly**: Review and update MongoDB version

