# Production Branch Guide

## Branch Created: `production`

This branch contains all production workload cluster configuration, completely separate from staging.

## Current Status

✅ **Branch**: `production` (created from current branch)
✅ **Files Added**: All `prod-workload` configuration files
✅ **Staging**: Unaffected (staging-ops and staging-workload remain unchanged)

## What's in This Branch

### Production Workload Cluster
```
argocd/applications/prod-workload/
├── applications/          # ArgoCD Application definitions
│   ├── cert-manager.yaml
│   ├── cluster-resources-app.yaml
│   ├── dareyscore.yaml
│   ├── external-dns.yaml
│   ├── external-secrets-operator.yaml
│   ├── kube-prometheus-stack.yaml
│   ├── lab-controller.yaml
│   ├── liveclasses.yaml
│   └── nginx-ingress.yaml
├── cluster-resources/     # Cluster-level resources
├── dareyscore/           # DareyScore application manifests
├── lab-controller/        # Lab Controller application manifests
└── liveclasses/          # Live Classes application manifests
```

## Next Steps

### 1. Complete Required Updates

Before committing, update these files:

**Cluster Endpoints:**
- Replace `REPLACE_WITH_PROD_WORKLOAD_CLUSTER_ENDPOINT` in all `applications/*.yaml` files

**AWS Secrets Manager Keys:**
- `dareyscore/external-secret-api.yaml` - Change `staging/dareyscore/*` → `prod/dareyscore/*`
- `lab-controller/external-secret-redis.yaml` - Change `staging/dareyscore/redis` → `prod/dareyscore/redis`
- `lab-controller/external-secret.yaml` - Change `staging/lab-controller/*` → `prod/lab-controller/*`
- `liveclasses/external-secret.yaml` - Change `staging/liveclasses/*` → `prod/liveclasses/*`

**IAM Role ARNs:**
- `dareyscore/serviceaccount.yaml` - Update role ARN
- `lab-controller/deployment.yaml` - Update ECR role ARN

### 2. Commit Changes

```bash
cd gitops

# Stage all production files
git add argocd/applications/prod-workload/

# Commit
git commit -m "Add production workload cluster configuration

- Created prod-workload as exact replica of staging-workload
- Updated labels: staging -> prod
- Updated paths: staging-workload -> prod-workload
- Updated DNS hostnames to prod-workload
- Added placeholder for cluster endpoint

Still requires:
- Cluster endpoint updates
- AWS Secrets Manager key updates
- IAM role ARN updates"
```

### 3. Push Branch

```bash
# Push production branch to remote
git push -u origin production
```

### 4. Create Pull Request (Optional)

Create a PR from `production` → `main` for review before merging.

## Working with Branches

### Switch to Production Branch
```bash
cd gitops
git checkout production
```

### Switch Back to Main/Staging
```bash
cd gitops
git checkout main  # or your default branch
```

### View Changes
```bash
# See what's different from main
git diff main..production

# See files changed
git diff --name-only main..production
```

## Safety

✅ **Staging is Safe**: 
- `staging-ops/` and `staging-workload/` are untouched
- No staging files modified
- Production files are completely separate

✅ **Isolation**:
- Production configuration in separate directory
- Production branch separate from main
- Can work on both without conflicts

## Merge Strategy

When ready to merge production to main:

```bash
# Option 1: Direct merge
git checkout main
git merge production
git push origin main

# Option 2: Create PR (recommended)
# Create PR on GitHub/GitLab from production -> main
# Review and merge via UI
```

## Verification

Before merging, verify:

- [ ] All cluster endpoints updated
- [ ] All AWS Secrets Manager keys updated to `prod/`
- [ ] All IAM role ARNs updated
- [ ] No staging references remain (except in comments)
- [ ] All applications can sync in ArgoCD
- [ ] Tested in non-production environment if possible

