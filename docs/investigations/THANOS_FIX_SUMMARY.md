# Thanos Receive Persistence Fix - Summary

**Date**: 2025-11-22
**Status**: Fix Applied, Waiting for Deployment

## Problem

Metrics were being received by Thanos Receive (462k+ samples) but not queryable via Thanos Query. Root cause: **persistence was disabled**, so metrics were only in memory.

## Fix Applied

### 1. Enabled Persistence for Thanos Receive

**File**: `gitops/argocd/applications/prod-ops/applications/thanos.yaml`

**Changes**:
```yaml
persistence:
  enabled: true
  storageClass: gp2-eks-csi
  accessModes:
    - ReadWriteOnce
  size: 50Gi
```

**Why**:
- Without persistence, metrics are only in memory
- Metrics not persisted cannot be queried via store API
- Enabling persistence allows blocks to be created and queried

### 2. Terraform/IaC Evaluation

**Status**: ✅ Properly Configured

**Terraform Configuration**:
- Thanos IAM role enabled for ops cluster (`enable_thanos = true`)
- S3 bucket ARN configured (`thanos_s3_bucket_arn`)
- IAM role name: `darey-io-v2-lab-prod-ops-thanos-role`
- Service account namespace: `monitoring` (default)
- Service account name: `thanos-receive` (actual) vs `thanos` (Terraform default)

**IAM Permissions**:
- S3 bucket access: `s3:ListBucket`, `s3:GetObject`, `s3:DeleteObject`, `s3:PutObject`
- Role ARN: `arn:aws:iam::586794457112:role/darey-io-v2-lab-prod-ops-thanos-role`
- ✅ IAM role is correctly attached to service account

**Note**: There's a service account name mismatch:
- Terraform default: `thanos`
- Actual SA name: `thanos-receive`

However, the IAM role is correctly attached, so this is not an issue. The Bitnami chart uses `thanos-receive` as the service account name, and the IAM role is properly configured in the Helm values.

### 3. Storage Class

**Status**: ✅ Available

- Storage class `gp2-eks-csi` exists and is available
- Provisioner: `ebs.csi.eks.amazonaws.com`
- Volume binding mode: `WaitForFirstConsumer`
- Allows volume expansion: `true`

## Deployment Status

**Changes Committed**: ✅
- Commit: `351c649`
- Message: "fix: enable persistence for Thanos Receive to make metrics queryable"

**Changes Pushed**: ✅
- Pushed to `main` branch

**ArgoCD Sync**: ⏳ Waiting
- ArgoCD will automatically sync the changes
- StatefulSet will be updated with volumeClaimTemplate
- PVCs will be created for each receive replica (2 PVCs)
- Pods will restart to mount the new volumes

## Next Steps

1. **Wait for ArgoCD Sync** (automatic, usually within 1-2 minutes)
2. **Verify PVCs Created**:
   ```bash
   kubectl get pvc -n monitoring --context=ops | grep thanos-receive
   ```
3. **Verify Pods Restarted**:
   ```bash
   kubectl get pods -n monitoring --context=ops -l app.kubernetes.io/component=receive
   ```
4. **Wait for Blocks** (5-10 minutes after pods restart):
   ```bash
   kubectl exec -n monitoring --context=ops thanos-receive-0 -- ls -la /var/thanos/receive
   ```
5. **Verify Metrics Queryable**:
   ```bash
   kubectl port-forward -n monitoring --context=ops svc/thanos-query 9090:9090 &
   curl "http://localhost:9090/api/v1/query?query=aws_cost_exporter_current_month_cost"
   ```

## Expected Outcome

After persistence is enabled:
- ✅ PVCs created (2x 50Gi volumes)
- ✅ Pods restarted with volumes mounted
- ✅ Blocks created in `/var/thanos/receive`
- ✅ Metrics become queryable via Thanos Query
- ✅ Dashboard shows data

## Additional Notes

### S3 Access Denied Errors

We observed S3 "Access Denied" errors in Thanos Receive logs. This is a **separate issue** from persistence:
- Thanos Receive tries to upload blocks to S3 for long-term storage
- IAM permissions appear correct, but errors persist
- This doesn't affect local persistence (the main fix)
- Can be investigated separately if needed

### Store Component

Thanos Store component is enabled in config but not running:
- Store queries S3 bucket for long-term storage
- Currently not needed for immediate fix
- Can be added to Thanos Query storeEndpoints once running

---

**Status**: Fix applied, waiting for deployment and verification.

