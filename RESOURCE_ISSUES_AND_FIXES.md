# Resource Issues and Fixes

## Issues Identified

### 1. **NodePool IAM Permissions (CRITICAL)**
**Problem**: NodePool `general-purpose` is unhealthy with error:
```
Error getting launch template configs: User is not authorized to perform this operation because no identity-based policy allows it
```

**Impact**: Karpenter (managed by EKS Auto Mode) cannot provision new nodes, causing:
- Pods failing to schedule due to insufficient CPU
- Only 2 nodes available (6 CPUs total) with ~4.45 CPUs requested by pods
- No automatic scaling when workloads need more resources

**Root Cause**: EKS Auto Mode's internal service role lacks `ec2:GetLaunchTemplateData` permission or related launch template permissions.

**Fix Required**: 
- Check EKS Auto Mode service role permissions in Terraform
- Ensure the EKS Auto Mode service role has permissions for:
  - `ec2:GetLaunchTemplateData`
  - `ec2:DescribeLaunchTemplates`
  - `ec2:DescribeLaunchTemplateVersions`
- The role name is: `darey-io-v2-lab-prod-green-eks-auto-2025111014140893400000000a`

### 2. **Grafana PVC Missing (FIXED)**
**Problem**: Grafana pod was pending because PVC `kube-prometheus-stack-grafana` didn't exist.

**Fix Applied**: Created PVC manually in `argocd/applications/prod-green/cluster-resources/grafana-pvc.yaml`

### 3. **Loki PVC Storage Class (FIXED)**
**Problem**: Loki PVC was missing `storageClassName`, causing it to remain pending.

**Fix Applied**: 
- Patched existing PVC to add `storageClassName: gp2`
- Updated Loki Helm values to ensure storageClassName is set

### 4. **CPU Capacity Constraints**
**Current State**:
- 2 nodes: 4 CPUs + 2 CPUs = 6 CPUs total
- Pods requesting: ~4.45 CPUs
- System overhead: ~0.5-1 CPU
- **Result**: Insufficient capacity for new pods

**Recommendations**:
1. Fix NodePool IAM permissions (see #1) to enable automatic scaling
2. Consider reducing resource requests for non-critical workloads
3. Monitor node provisioning once IAM is fixed

## Resource Requests Summary

### High CPU Consumers:
- Prometheus: 500m CPU request
- Loki: 400m CPU request  
- Worker pods (5x): 250m each = 1.25 CPUs total
- API pods (5x): ~200m each = 1 CPU total
- System pods: ~500m-1 CPU

### Total: ~4.45 CPUs requested (excluding system overhead)

## Next Steps

1. **URGENT**: Fix EKS Auto Mode IAM permissions in Terraform
2. Monitor node provisioning after IAM fix
3. Consider reducing worker replicas from 5 to 3 if not needed
4. Verify Grafana and Loki pods start after PVC fixes

## Verification Commands

```bash
# Check NodePool status
kubectl get nodepool general-purpose --context=darey-io-v2-lab-prod-green -o yaml

# Check pending pods
kubectl get pods -A --context=darey-io-v2-lab-prod-green --field-selector=status.phase!=Running,status.phase!=Succeeded

# Check PVC status
kubectl get pvc -A --context=darey-io-v2-lab-prod-green

# Check node capacity
kubectl get nodes --context=darey-io-v2-lab-prod-green -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.cpu}{"\n"}{end}'
```

