# Jitsi Management via GitOps

## Problem

Jitsi deployments were coming back online even when disabled because:
1. ArgoCD was syncing the base directory without a root-level `kustomization.yaml`
2. Without a root `kustomization.yaml`, ArgoCD may sync all YAML files in the directory
3. Jitsi deployment files existed in the directory but weren't explicitly excluded

## Solution

### Root Kustomization

Created `kustomization.yaml` at the root of `liveclasses/` directory that:
- Uses the `base` kustomization (which excludes Jitsi)
- Ensures only resources listed in kustomization are synced
- Allows ArgoCD's `prune: true` to delete Jitsi deployments when not included

### Base Kustomization

The `base/kustomization.yaml`:
- Includes only BBB, MongoDB, and shared resources
- **Excludes all Jitsi resources** (jitsi-web, jicofo, jvb, prosody, jibri)
- Has correct relative paths for resources

### ConfigMap

The `configmap.yaml` sets:
- `jitsi_enabled: "false"` (default)
- `bbb_enabled: "true"`
- `provider: "bbb"`

## How It Works

1. **ArgoCD syncs** `argocd/applications/prod-workload/liveclasses/`
2. **Kustomize processes** the root `kustomization.yaml`
3. **Only resources listed** in kustomization are included
4. **ArgoCD prune: true** deletes resources not in kustomization
5. **Jitsi deployments are pruned** because they're not listed

## Enabling Jitsi

To enable Jitsi, you have two options:

### Option 1: Use Overlay (Recommended)

Update ArgoCD application to use overlay:
```yaml
spec:
  source:
    path: argocd/applications/prod-workload/liveclasses/overlays/jitsi-enabled
```

### Option 2: Add to Root Kustomization

Add Jitsi resources to root `kustomization.yaml`:
```yaml
resources:
  - base
  - jitsi-web-deployment.yaml
  - jicofo-deployment.yaml
  - jvb-deployment.yaml
  - prosody-deployment.yaml
  - jibri-deployment.yaml
  # ... other Jitsi resources
```

And update ConfigMap:
```yaml
jitsi_enabled: "true"
```

## Disabling Jitsi

1. Remove Jitsi resources from root `kustomization.yaml` (or use `jitsi-disabled` overlay)
2. Update ConfigMap: `jitsi_enabled: "false"`
3. Commit and push
4. ArgoCD will prune Jitsi deployments automatically

## Verification

After ArgoCD syncs:
```bash
# Jitsi deployments should be gone
kubectl get deployment -n liveclasses | grep -E "jitsi|jibri|jicofo|jvb|prosody"

# ConfigMap should show disabled
kubectl get configmap liveclasses-config -n liveclasses -o jsonpath='{.data.jitsi_enabled}'
# Should output: false
```

## Important Notes

- **Never use kubectl apply** - All changes go through GitOps
- **Jitsi files can remain in directory** - They're just not included in kustomization
- **ArgoCD prune** will delete them when not in kustomization
- **ConfigMap flag** is informational - actual control is via kustomization.yaml

