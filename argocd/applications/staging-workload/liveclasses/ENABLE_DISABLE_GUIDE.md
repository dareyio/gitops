# Enable/Disable BBB or Jitsi Guide

This guide explains how to enable or disable BBB or Jitsi streaming providers in the liveclasses application.

## Quick Reference

### Enable BBB
1. Update `liveclasses-config.yaml`: Set `provider: "bbb"`, `bbb_enabled: "true"`, `jitsi_enabled: "false"`
2. Update `kustomization.yaml`: Uncomment `- bbb` in resources list
3. Commit and push

### Disable BBB
1. Update `liveclasses-config.yaml`: Set `provider: "jitsi"`, `bbb_enabled: "false"`, `jitsi_enabled: "true"`
2. Update `kustomization.yaml`: Comment out or remove `- bbb` from resources list
3. Commit and push

### Enable Jitsi
1. Update `liveclasses-config.yaml`: Set `provider: "jitsi"`, `jitsi_enabled: "true"`, `bbb_enabled: "false"`
2. Ensure Jitsi resources are in `kustomization.yaml` (they are by default)
3. Commit and push

### Disable Jitsi
1. Update `liveclasses-config.yaml`: Set `jitsi_enabled: "false"`
2. Comment out all Jitsi resources in `kustomization.yaml`
3. Commit and push

## Detailed Steps

### Step 1: Update Configuration

Edit `liveclasses-config.yaml`:

**For BBB:**
```yaml
provider: "bbb"
bbb_enabled: "true"
jitsi_enabled: "false"
default_path: "/bbb"
```

**For Jitsi:**
```yaml
provider: "jitsi"
jitsi_enabled: "true"
bbb_enabled: "false"
default_path: "/jitsi"
```

### Step 2: Update Kustomization

Edit `kustomization.yaml`:

**To Enable BBB:**
```yaml
resources:
  - namespace.yaml
  - liveclasses-config.yaml
  - liveclasses-recordings-serviceaccount.yaml
  - liveclasses-streaming-ingress.yaml
  - bbb  # <-- Uncomment this line
  # Jitsi resources...
```

**To Disable BBB:**
```yaml
resources:
  - namespace.yaml
  - liveclasses-config.yaml
  - liveclasses-recordings-serviceaccount.yaml
  - liveclasses-streaming-ingress.yaml
  # - bbb  # <-- Comment out or remove this line
  # Jitsi resources...
```

### Step 3: Update Ingress (Optional)

If switching providers, update `liveclasses-streaming-ingress.yaml` to route the default path correctly:

**For BBB:**
```yaml
- path: /
  pathType: Prefix
  backend:
    service:
      name: liveclasses-bbb-api
      port:
        number: 8080
```

**For Jitsi:**
```yaml
- path: /
  pathType: Prefix
  backend:
    service:
      name: jitsi-web
      port:
        number: 80
```

### Step 4: Commit and Push

```bash
git add .
git commit -m "Switch streaming provider to [BBB|Jitsi]"
git push
```

ArgoCD will automatically sync and deploy/remove resources.

## Verification

After switching providers, verify the deployment:

```bash
# Check deployments
kubectl get deployments -n liveclasses

# Check pods
kubectl get pods -n liveclasses

# Check services
kubectl get services -n liveclasses

# Check for any remaining resources from the disabled provider
kubectl get all -n liveclasses | grep -E "bbb|jitsi|mongodb|freeswitch|kurento|etherpad|greenlight|redis|prosody|jicofo|jvb"
```

## What Gets Deployed/Removed

### BBB Bundle (when `- bbb` is included)
- All components listed in `bbb/kustomization.yaml`
- See `BBB_COMPONENTS.md` for complete list
- Includes: bbb-api, bbb-web, mongodb, freeswitch, kurento, etherpad, greenlight, redis, and all related configs/secrets

### Jitsi Bundle (when Jitsi resources are included)
- prosody, jicofo, jvb, jitsi-web, jibri
- All related configmaps, secrets, and services
- See `kustomization.yaml` for complete list

## Important Notes

1. **PVCs**: MongoDB PVCs are NOT automatically deleted when BBB is disabled (data preservation). To delete:
   ```bash
   kubectl delete pvc -n liveclasses -l app=mongodb
   ```

2. **ArgoCD Pruning**: With `prune: true` in ArgoCD sync policy, resources removed from kustomization will be automatically deleted.

3. **Shared Resources**: Some resources like `liveclasses-streaming-ingress.yaml` are shared and need manual updates when switching providers.

4. **TURN Server**: `coturn` and `turn-credentials-api` are NOT included in either bundle as they may be shared.

5. **HPAs**: HPAs are defined inline in deployment files and are automatically included/excluded with their deployments.

## Troubleshooting

### Resources not being pruned
- Check ArgoCD sync status: `kubectl get applications -n argocd`
- Verify `prune: true` in ArgoCD application sync policy
- Manually delete if needed: `kubectl delete <resource-type> -n liveclasses <resource-name>`

### Resources not being created
- Verify kustomization is valid: `kubectl kustomize argocd/applications/staging-workload/liveclasses`
- Check ArgoCD sync logs
- Verify all referenced files exist

### Configuration issues
- Check `liveclasses-config.yaml` values match the enabled provider
- Verify ingress routes point to correct services
- Check service names match deployment labels

