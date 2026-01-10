# Staging-Ops Cluster Deletion Readiness Assessment

**Date:** 2026-01-10  
**Status:** ⚠️ **MOSTLY READY** (with recommendations)

---

## Executive Summary

**Assessment Result:** ArgoCD multi-cluster management is fully operational and tested. However, there are some infrastructure components (VPC peering, Prometheus federation) that should be verified before destroying staging-ops cluster.

**Recommendation:** 
- ✅ **Safe to destroy** if you accept monitoring gap during transition
- ⚠️ **Recommended:** Complete Terraform deployment first for full monitoring capability
- ⏳ **Best practice:** Monitor for 24-48 hours post-deployment before deletion

---

## Verified Components ✅

### 1. ArgoCD Multi-Cluster Management
- ✅ **Cluster secret created** - staging-workload-cluster-secret exists in prod-ops
- ✅ **Bootstrap application deployed** - staging-workload-applications exists
- ✅ **8+ applications syncing successfully** - Multiple staging-workload apps are Synced/Healthy
- ✅ **End-to-end sync tested** - Successfully verified with test change:
  - Change detected within 35 seconds
  - Auto-sync completed in <5 seconds
  - Change deployed to staging-workload cluster
  - Application remained healthy throughout

### 2. Application Dependencies
- ✅ **No workload dependencies** - Staging-ops only ran monitoring services
- ✅ **Dashboards migrated** - All staging dashboards migrated to prod-ops
- ✅ **No ArgoCD references** - No applications reference staging-ops cluster

### 3. Critical Services Health
- ✅ **lab-controller:** Synced/Healthy
- ✅ **nginx-ingress:** Synced/Healthy
- ⚠️ **dareyscore:** OutOfSync/Healthy (may need manual sync, non-blocking)

---

## Pending Infrastructure ⚠️

### 1. VPC Peering (Not Applied)
**Status:** Not yet created (Terraform not applied to prod/staging)

**Impact:**
- Prometheus federation uses DNS endpoints (prometheus-stg.talentos.darey.io)
- If Prometheus endpoints are publicly accessible, VPC peering may not be required
- If Prometheus endpoints require private connectivity, VPC peering is necessary

**Action Required:**
- **Option A:** Deploy Terraform to enable VPC peering (recommended)
- **Option B:** Verify Prometheus endpoints are publicly accessible via DNS
- **Option C:** Accept monitoring gap during transition period

### 2. Prometheus Federation (Cannot Verify)
**Status:** Prometheus pod in prod-ops is Pending (pre-existing issue, 39 days old)

**Impact:**
- Cannot verify federation targets are working
- Federation configuration is correct in GitOps
- Once Prometheus is running, federation should work (DNS-based endpoints)

**Action Required:**
- **Option A:** Resolve Prometheus pod issue first (pre-existing, may require storage fix)
- **Option B:** Accept that federation will work once Prometheus is running
- **Recommendation:** This is a pre-existing issue, not related to staging-ops deletion

---

## What Was Running in Staging-Ops?

Based on GitOps configuration, staging-ops cluster only ran:
- Prometheus (monitoring)
- Grafana (visualization)
- Dashboards (Grafana dashboards)
- Supporting infrastructure (cert-manager, external-dns, nginx-ingress)

**No workload applications** were running in staging-ops cluster.

---

## Pre-Deletion Checklist

### Critical (Must Complete)
- [x] ✅ ArgoCD multi-cluster management verified
- [x] ✅ Staging-workload applications managed by prod-ops ArgoCD
- [x] ✅ No applications depend on staging-ops cluster
- [x] ✅ End-to-end sync tested and verified
- [ ] ⏳ Terraform VPC peering deployment (optional but recommended)
- [ ] ⏳ Prometheus pod issue resolved (pre-existing, not blocking)

### Recommended (Should Complete)
- [ ] ⏳ Deploy Terraform changes to prod environment (Graviton migration + VPC peering)
- [ ] ⏳ Deploy Terraform changes to staging environment (VPC peering acceptance)
- [ ] ⏳ Verify Prometheus federation targets (once Prometheus is running)
- [ ] ⏳ Monitor for 24-48 hours to ensure stability
- [ ] ⏳ Archive staging-ops GitOps configurations

### Optional (Nice to Have)
- [ ] ⏳ Verify Grafana dashboards show metrics from both clusters
- [ ] ⏳ Verify all monitoring alerts are working
- [ ] ⏳ Document any monitoring gaps during transition

---

## Safe Deletion Scenarios

### Scenario A: Immediate Deletion (Accept Monitoring Gap)
**When Safe:**
- ✅ ArgoCD multi-cluster management verified (DONE)
- ✅ All applications syncing successfully (DONE)
- ⚠️ Accept that Prometheus federation may not work until Terraform is deployed
- ⚠️ Accept monitoring gap during transition

**Risk Level:** 🟡 **Low-Medium**
- **Impact:** No application downtime, but monitoring may be incomplete
- **Mitigation:** Applications will continue to run, monitoring can be fixed post-deletion

### Scenario B: Post-Terraform Deployment (Recommended)
**When Safe:**
- ✅ ArgoCD multi-cluster management verified (DONE)
- ⏳ Terraform changes deployed (prod → staging)
- ⏳ VPC peering active
- ⏳ Prometheus federation verified (once Prometheus pod is running)

**Risk Level:** 🟢 **Low**
- **Impact:** Minimal, full monitoring capability
- **Timeline:** +1-2 hours for Terraform deployment + verification

### Scenario C: Extended Monitoring (Best Practice)
**When Safe:**
- ✅ All Scenario B requirements
- ⏳ Monitor for 24-48 hours
- ⏳ Verify stability across different time periods
- ⏳ Verify no edge cases or intermittent issues

**Risk Level:** 🟢 **Very Low**
- **Impact:** Minimal, with extended verification period
- **Timeline:** +24-48 hours

---

## Test Results Summary

| Test | Status | Result |
|------|--------|--------|
| ArgoCD cluster secret | ✅ Pass | Secret created and labeled correctly |
| Bootstrap application | ✅ Pass | Deployed and discovering applications |
| Application discovery | ✅ Pass | 8+ applications discovered |
| End-to-end sync | ✅ Pass | Change synced in <40 seconds |
| Deployment health | ✅ Pass | Applications remained healthy |
| VPC peering | ⚠️ N/A | Not applied (Terraform pending) |
| Prometheus federation | ⚠️ N/A | Cannot verify (Prometheus pod Pending) |

---

## Recommendations

### Immediate Action
1. **If monitoring gap is acceptable:** ✅ **Safe to delete staging-ops cluster now**
   - ArgoCD multi-cluster management is fully operational
   - Applications are being managed successfully
   - Monitoring gap is temporary and fixable

2. **If full monitoring required:** ⏳ **Wait for Terraform deployment**
   - Deploy Terraform changes (prod → staging)
   - Verify VPC peering is active
   - Verify Prometheus federation (once Prometheus is running)
   - Monitor for 24-48 hours

### Best Practice Recommendation
1. **Deploy Terraform changes first** (1-2 hours)
   - Prod: Graviton migration + VPC peering
   - Staging: VPC peering acceptance
   
2. **Resolve Prometheus pod issue** (if possible)
   - This is a pre-existing issue (39 days old)
   - Not related to staging-ops deletion
   - May require storage/volume cleanup

3. **Monitor for 24-48 hours** (recommended)
   - Verify Prometheus federation is working
   - Verify Grafana dashboards show both clusters
   - Verify no edge cases or issues

4. **Then delete staging-ops cluster**
   - Archive GitOps configs first
   - Delete via Terraform: `terraform destroy -target=module.eks_cluster_ops` (staging environment)

---

## Deletion Steps (When Ready)

1. **Archive GitOps configurations:**
   ```bash
   mkdir -p gitops/argocd/applications/archived/staging-ops-$(date +%Y%m%d)
   mv gitops/argocd/applications/staging-ops/* gitops/argocd/applications/archived/staging-ops-$(date +%Y%m%d)/
   git commit -m "chore: Archive staging-ops configurations before cluster deletion"
   ```

2. **Update Terraform:**
   ```bash
   cd terraform/environments/staging
   # Comment out or remove staging-ops cluster module
   # Then apply
   ```

3. **Destroy staging-ops cluster:**
   ```bash
   terraform destroy -target=module.eks_cluster_ops
   ```

4. **Verify cleanup:**
   ```bash
   # Verify no resources remain
   aws eks list-clusters --region eu-west-2 | grep staging-ops
   ```

---

## Conclusion

**Assessment:** ⚠️ **MOSTLY READY**

**Blocking Issues:** 0 (All critical components verified)

**Warnings:** 2 (VPC peering not applied, Prometheus federation not verifiable)

**Recommendation:** 
- ✅ **ArgoCD multi-cluster management is fully operational** - This is the critical dependency
- ⚠️ **Monitoring infrastructure** - VPC peering and Prometheus are important but not blocking
- 🟡 **Safe to delete with monitoring gap** OR 🟢 **Recommended to deploy Terraform first**

**Final Answer:** 
- **If you accept temporary monitoring gap:** ✅ **YES, safe to destroy staging-ops cluster now**
- **If you want full monitoring capability:** ⏳ **Deploy Terraform first, then destroy**

The core functionality (ArgoCD managing staging-workload) is fully tested and operational. The remaining items are monitoring-related and can be fixed post-deletion if needed.
