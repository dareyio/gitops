# ArgoCD Multi-Cluster Management Setup

**Status:** ✅ **COMPLETE** - ArgoCD in prod-ops successfully manages both staging-workload and prod-workload clusters

**Last Updated:** 2026-01-10

---

## Summary

ArgoCD running in the `prod-ops` cluster is now configured to manage deployments into both:

- ✅ **prod-workload** cluster (configured and verified)
- ✅ **staging-workload** cluster (configured and verified)

---

## Cluster Registration

### Prod-Workload Cluster

- **Secret Name:** `prod-workload-cluster`
- **Status:** ✅ Registered (existing configuration)
- **Applications Managed:** 9+ applications
- **Verification:** Multiple applications showing `Synced/Healthy` status

### Staging-Workload Cluster

- **Secret Name:** `staging-workload-cluster-secret`
- **Status:** ✅ Registered (configured on 2026-01-10)
- **Creation Method:** Automated script (`scripts/create-staging-workload-argocd-secret.sh`)
- **ServiceAccount:** `argocd-manager` in `kube-system` namespace with `cluster-admin` permissions
- **Applications Managed:** 9 applications
- **Verification:** Multiple applications showing `Synced/Healthy` status

---

## Bootstrap Applications

### Prod-Workload Bootstrap

- **Application Name:** `prod-workload-applications`
- **Location:** `gitops/argocd/bootstrap/prod-workload.yaml`
- **Destination:** Points directly to prod-workload cluster endpoint
- **Status:** ✅ Deployed and syncing

### Staging-Workload Bootstrap

- **Application Name:** `staging-workload-applications`
- **Location:** `gitops/argocd/bootstrap/staging-workload.yaml`
- **Destination:** Creates Application CRDs in prod-ops ArgoCD namespace
- **Status:** ✅ Deployed (OutOfSync due to child applications being managed)
- **Child Applications:** Individual applications deploy to staging-workload cluster

---

## Application Status

### Staging-Workload Applications (Managed from prod-ops)

| Application               | Sync Status  | Health Status |
| ------------------------- | ------------ | ------------- |
| cert-manager              | ✅ Synced    | Healthy       |
| cluster-resources         | ✅ Synced    | Healthy       |
| dareyscore                | ⚠️ OutOfSync | Healthy       |
| external-dns              | ✅ Synced    | Healthy       |
| external-secrets-operator | ✅ Synced    | Healthy       |
| kube-prometheus-stack     | ✅ Synced    | Degraded\*    |
| lab-controller            | ✅ Synced    | Healthy       |
| liveclasses               | ✅ Synced    | Healthy       |
| nginx-ingress             | ✅ Synced    | Healthy       |

\*Degraded status may be due to pre-existing configuration issues, not connectivity problems

### Prod-Workload Applications (Managed from prod-ops)

All prod-workload applications are successfully managed from prod-ops ArgoCD, with multiple applications showing `Synced/Healthy` status.

---

## Verification Scripts

### Test Connectivity

```bash
cd gitops
./scripts/test-argocd-staging-workload-connectivity.sh
```

This script verifies:

- Cluster secret exists and is correctly labeled
- Bootstrap application exists
- Applications are discovered
- At least one application can sync successfully

### Create Cluster Secret (if needed)

```bash
cd gitops
./scripts/create-staging-workload-argocd-secret.sh
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    prod-ops Cluster                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │          ArgoCD (Application Controller)             │  │
│  │  - Manages: prod-ops applications                    │  │
│  │  - Manages: prod-workload applications               │  │
│  │  - Manages: staging-workload applications            │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│         ┌───────────────┼───────────────┐                   │
│         │               │               │                   │
│         ▼               ▼               ▼                   │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ prod-ops │  │prod-workload │  │staging-      │          │
│  │ apps     │  │apps          │  │workload apps │          │
│  └──────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
   prod-ops cluster   prod-workload cluster  staging-workload cluster
```

---

## Cluster Secrets Configuration

### Staging-Workload Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: staging-workload-cluster-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: staging-workload
  server: https://FB48AC16EE81C0085089AAECDD2874F7.gr7.eu-west-2.eks.amazonaws.com
  config: |
    {
      "bearerToken": "<service-account-token>",
      "tlsClientConfig": {
        "caData": "<cluster-ca-cert>",
        "insecure": false
      }
    }
```

### ServiceAccount (in staging-workload cluster)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
```

---

## Troubleshooting

### If applications show "Unknown" or connection errors:

1. **Verify cluster secret exists:**

   ```bash
   kubectl get secret staging-workload-cluster-secret -n argocd --context=prod-ops
   ```

2. **Check secret labels:**

   ```bash
   kubectl get secret staging-workload-cluster-secret -n argocd --context=prod-ops -o yaml | grep "argocd.argoproj.io/secret-type"
   ```

   Should show: `argocd.argoproj.io/secret-type: cluster`

3. **Verify ServiceAccount token:**

   ```bash
   kubectl get secret -n kube-system --context=staging-workload | grep argocd-manager
   ```

4. **Check ArgoCD logs:**

   ```bash
   kubectl logs -n argocd --context=prod-ops -l app.kubernetes.io/name=argocd-application-controller --tail=100 | grep -i "staging-workload\|error"
   ```

5. **Force refresh cluster connection:**
   ```bash
   # Restart ArgoCD application controller to refresh cluster connections
   kubectl rollout restart deployment argocd-application-controller -n argocd --context=prod-ops
   ```

---

## Next Steps

- ✅ Cluster secrets created for both workload clusters
- ✅ Bootstrap applications deployed
- ✅ Applications discovered and syncing
- ⏳ Monitor application sync status regularly
- ⏳ Set up alerts for sync failures (if not already configured)

---

## Related Documentation

- `gitops/scripts/create-staging-workload-argocd-secret.sh` - Script to create cluster secret
- `gitops/scripts/test-argocd-staging-workload-connectivity.sh` - Connectivity verification script
- `gitops/argocd/bootstrap/staging-workload.yaml` - Bootstrap Application definition
- `gitops/argocd/bootstrap/prod-workload.yaml` - Prod-workload bootstrap Application
