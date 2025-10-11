# GitOps Repository - Application Deployments

This repository contains ArgoCD configurations for deploying applications to Kubernetes clusters managed by the [dareyio/terraform](https://github.com/dareyio/terraform) repository.

## Repository Purpose

This is a **GitOps repository** where:

- Application deployments are defined as code
- ArgoCD automatically syncs changes to Kubernetes
- Infrastructure is separated from application definitions
- Each environment (dev, staging, prod) has isolated configurations

## Directory Structure

```
gitops/
├── .github/
│   └── scripts/
│       └── setup-deploy-keys.sh    # SSH key generation for ArgoCD
├── argocd/
│   ├── bootstrap/                   # App-of-apps (root applications)
│   │   ├── dev.yaml                # Dev environment root app
│   │   ├── staging.yaml            # Staging environment root app
│   │   └── prod.yaml               # Prod environment root app
│   └── applications/                # Individual application definitions
│       ├── dev/
│       │   ├── kube-prometheus-stack.yaml
│       │   └── loki.yaml
│       ├── staging/
│       │   └── (add applications here)
│       └── prod/
│           └── (add applications here)
├── .gitignore                       # Excludes SSH keys and sensitive files
└── README.md                        # This file
```

## How It Works

### App-of-Apps Pattern

This repository uses the **App-of-Apps pattern**:

1. **Bootstrap App**: Created by Terraform, points to `argocd/bootstrap/{environment}.yaml`
2. **Root App**: Monitors `argocd/applications/{environment}/` directory
3. **Child Apps**: Each YAML file defines an application to deploy

```
Terraform creates bootstrap app
  ↓
Bootstrap app watches argocd/bootstrap/{env}.yaml
  ↓
Root app watches argocd/applications/{env}/
  ↓
ArgoCD deploys all applications in that directory
```

### Deployment Flow

```
Developer commits → Git push → ArgoCD syncs (within 3 minutes) → Applications deployed
```

No manual kubectl or helm commands needed!

## Current Applications

### Dev Environment

**kube-prometheus-stack**:

- **Purpose**: Complete monitoring solution (Prometheus + Grafana + Alertmanager)
- **Namespace**: `monitoring`
- **Chart**: prometheus-community/kube-prometheus-stack v56.0.0
- **Features**:
  - 30-day retention
  - 50Gi persistent storage
  - Grafana dashboard included
- **Access**: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
- **Credentials**: admin/admin (change on first login)

**Loki**:

- **Purpose**: Log aggregation and querying
- **Namespace**: `monitoring`
- **Chart**: grafana/loki-stack v2.10.0
- **Features**:
  - 10Gi persistent storage
  - Promtail for log collection
  - Integrated with Grafana
- **Access**: View logs in Grafana (Explore → Loki data source)

### Staging/Prod Environments

Currently empty. Add application YAML files to deploy.

## Adding New Applications

### Option 1: Helm Chart from Repository

Create `argocd/applications/{env}/your-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: your-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.example.com
    chart: your-app-chart
    targetRevision: 1.0.0
    helm:
      valuesObject:
        replicas: 3
        image:
          tag: v1.0.0
  destination:
    server: https://kubernetes.default.svc
    namespace: your-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Option 2: Kustomize Manifests

1. Create manifests directory (if needed)
2. Create application pointing to manifests
3. Commit and push

### Workflow

1. Create application YAML file
2. Commit: `git add . && git commit -m "feat: add new application"`
3. Push: `git push origin main`
4. ArgoCD syncs automatically (within 3 minutes)
5. Monitor in ArgoCD UI

## Accessing ArgoCD

### Get Password

```bash
# Option 1: From Kubernetes
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Option 2: From Terraform output
cd /path/to/terraform
terraform output -raw argocd_admin_password
```

### Access UI

**Via Port Forward**:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit https://localhost:8080
```

**Via Ingress** (if configured):

```
https://argocd.{your-domain}.com
```

**Login**:

- Username: `admin`
- Password: (from command above)

⚠️ Change the admin password on first login!

## ArgoCD CLI

### Install

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

### Usage

```bash
# Port forward first
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login
argocd login localhost:8080

# List applications
argocd app list

# Get application status
argocd app get kube-prometheus-stack

# Sync application manually
argocd app sync kube-prometheus-stack

# View logs
argocd app logs kube-prometheus-stack
```

## SSH Key Setup

### Generate Keys

From the gitops repository root:

```bash
./.github/scripts/setup-deploy-keys.sh
```

This generates:

- `.ssh/argocd-deploy-key` (private - keep secure!)
- `.ssh/argocd-deploy-key.pub` (public - add to GitHub)

### Add to GitHub

**1. Add Public Key to GitOps Repo**:

- Go to: https://github.com/dareyio/gitops/settings/keys
- Click "Add deploy key"
- Title: "ArgoCD Deploy Key"
- Paste public key
- **Do NOT check "Allow write access"** (read-only)

**2. Add Private Key to Terraform Repo Secrets**:

- Go to: https://github.com/dareyio/terraform/settings/secrets/actions
- Click "New repository secret"
- Name: `ARGOCD_SSH_PRIVATE_KEY`
- Paste private key content

### Why Two Locations?

- **Public key** → GitOps repo (allows ArgoCD to read application configs)
- **Private key** → Terraform repo (Terraform creates Kubernetes secret for ArgoCD)

## Environment Management

### Dev Environment

- **Purpose**: Development and testing
- **Auto-sync**: Enabled (immediate deployment)
- **Applications**: Prometheus, Loki
- **Access**: Open for experimentation

### Staging Environment

- **Purpose**: Pre-production testing
- **Auto-sync**: Enabled
- **Applications**: (Add as needed)
- **Access**: Similar to production

### Prod Environment

- **Purpose**: Production workloads
- **Auto-sync**: Consider manual sync for critical apps
- **Applications**: (Promote from staging)
- **Access**: Restricted

## Best Practices

### 1. Testing Changes

Always test in dev before deploying to prod:

```bash
# 1. Create feature branch
git checkout -b feature/update-prometheus

# 2. Make changes to dev applications
vim argocd/applications/dev/kube-prometheus-stack.yaml

# 3. Commit and push
git commit -am "feat: update prometheus retention"
git push origin feature/update-prometheus

# 4. Test in dev environment
# ArgoCD syncs automatically

# 5. After verification, merge to main
# 6. Promote to staging/prod when ready
```

### 2. Promoting to Production

```bash
# Copy tested application from dev to prod
cp argocd/applications/dev/your-app.yaml argocd/applications/prod/

# Adjust prod-specific values
vim argocd/applications/prod/your-app.yaml

# Commit and deploy
git commit -am "feat: promote your-app to production"
git push origin main
```

### 3. Rollback

```bash
# Option 1: Git revert
git revert HEAD
git push origin main

# Option 2: ArgoCD UI
# Applications → Select app → History → Rollback

# Option 3: ArgoCD CLI
argocd app rollback your-app <revision>
```

### 4. Sync Policies

**Auto-sync** (recommended for dev):

```yaml
syncPolicy:
  automated:
    prune: true # Remove resources deleted from git
    selfHeal: true # Revert manual changes
```

**Manual sync** (for critical prod apps):

```yaml
syncPolicy:
  automated: {} # Empty or omit
```

## Monitoring Applications

### ArgoCD UI

Shows real-time status:

- Sync status (Synced, OutOfSync, Unknown)
- Health status (Healthy, Progressing, Degraded)
- Resource tree visualization
- Deployment history

### CLI Commands

```bash
# List all applications
argocd app list

# Get detailed status
argocd app get kube-prometheus-stack

# View sync history
argocd app history kube-prometheus-stack

# Watch sync progress
argocd app sync kube-prometheus-stack --watch
```

### Kubectl Commands

```bash
# List ArgoCD applications
kubectl get applications -n argocd

# Describe application
kubectl describe application kube-prometheus-stack -n argocd

# View application resources
kubectl get all -n monitoring
```

## Troubleshooting

### Application Not Syncing

```bash
# Check application status
kubectl describe application your-app -n argocd

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force refresh
argocd app get your-app --refresh
```

### SSH Connection Issues

```bash
# Verify SSH secret exists
kubectl get secret argocd-repo-ssh -n argocd

# Check secret format
kubectl get secret argocd-repo-ssh -n argocd -o yaml

# Test SSH key locally
ssh -T git@github.com -i .ssh/argocd-deploy-key
# Should respond: "Hi dareyio/gitops! You've successfully authenticated..."
```

### Application Degraded

```bash
# Check resources in namespace
kubectl get all -n your-namespace

# View events
kubectl get events -n your-namespace --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -n your-namespace <pod-name>

# View in ArgoCD UI for detailed error messages
```

### Sync Conflicts

If manual changes conflict with Git:

```bash
# Option 1: Let ArgoCD override (if selfHeal enabled)
# Wait 3 minutes for auto-sync

# Option 2: Manual sync with replace
argocd app sync your-app --replace

# Option 3: Reset to git state
kubectl delete application your-app -n argocd
# ArgoCD recreates from git
```

## Security

### Secrets Management

**Do NOT commit secrets to this repository!**

Use one of these approaches:

1. **Sealed Secrets**: Encrypt secrets before committing
2. **External Secrets Operator**: Reference secrets from AWS Secrets Manager
3. **ArgoCD Vault Plugin**: Integrate with HashiCorp Vault

Example with Sealed Secrets:

```bash
# Install kubeseal
brew install kubeseal

# Seal a secret
kubectl create secret generic my-secret --dry-run=client -o yaml | \
  kubeseal -o yaml > sealed-secret.yaml

# Commit sealed-secret.yaml safely
```

### SSH Key Rotation

To rotate ArgoCD deploy keys:

1. Generate new keys: `./.github/scripts/setup-deploy-keys.sh`
2. Add new public key to GitHub (keep old one)
3. Update `ARGOCD_SSH_PRIVATE_KEY` secret in terraform repo
4. Deploy terraform (creates new Kubernetes secret)
5. Verify ArgoCD syncs successfully
6. Remove old deploy key from GitHub

## Integration with Terraform

The [dareyio/terraform](https://github.com/dareyio/terraform) repository:

- Deploys the Kubernetes cluster (EKS)
- Installs ArgoCD via Helm
- Creates SSH secret for this repository
- Bootstraps the app-of-apps pattern

### Infrastructure vs Applications

| Component        | Repository | Deployment              |
| ---------------- | ---------- | ----------------------- |
| EKS Cluster      | terraform  | Git tags (immutable)    |
| VPC/Networking   | terraform  | Git tags                |
| ArgoCD           | terraform  | Git tags                |
| NGINX Ingress    | terraform  | Git tags                |
| **Applications** | **gitops** | **Continuous (ArgoCD)** |
| **Monitoring**   | **gitops** | **Continuous (ArgoCD)** |

**Key Principle**: Infrastructure changes via tags (manual approval), application changes deploy automatically.

## Repository Workflow

### Development

```bash
# 1. Create feature branch
git checkout -b feature/new-app

# 2. Add application
vim argocd/applications/dev/new-app.yaml

# 3. Commit and push
git add .
git commit -m "feat: add new application"
git push origin feature/new-app

# 4. Create PR, review, merge
```

### Production Deployment

```bash
# After testing in dev/staging
# Copy to prod directory
cp argocd/applications/dev/app.yaml argocd/applications/prod/

# Adjust for production
vim argocd/applications/prod/app.yaml

# Commit to main
git add .
git commit -m "feat: deploy app to production"
git push origin main
```

## Grafana Access

After kube-prometheus-stack is deployed:

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Visit http://localhost:3000
# Username: admin
# Password: admin (change immediately!)
```

### Add Loki Data Source in Grafana

1. Go to Configuration → Data Sources
2. Click "Add data source"
3. Select "Loki"
4. URL: `http://loki:3100`
5. Click "Save & Test"

Now you can query logs in Grafana Explore!

## Prometheus Access

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Visit http://localhost:9090
```

## Alertmanager Access

```bash
# Port forward Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Visit http://localhost:9093
```

## Common Tasks

### Update Application Version

```yaml
# In argocd/applications/dev/your-app.yaml
spec:
  source:
    targetRevision: 2.0.0 # Update version
```

Commit and push - ArgoCD updates automatically.

### Change Helm Values

```yaml
helm:
  valuesObject:
    replicas: 5 # Increase replicas
    resources:
      limits:
        cpu: 2000m
```

### Disable Auto-Sync for Production

```yaml
syncPolicy:
  automated: {} # Empty = manual sync only
```

Then sync manually in ArgoCD UI or CLI.

### Add New Environment

1. Create directory: `argocd/applications/uat/`
2. Create bootstrap: `argocd/bootstrap/uat.yaml`
3. Add applications
4. Update terraform to bootstrap UAT environment

## Monitoring

### Application Health

- **Healthy**: All resources running correctly
- **Progressing**: Deployment in progress
- **Degraded**: Some resources failing
- **Suspended**: Sync disabled
- **Unknown**: ArgoCD can't determine status

### Sync Status

- **Synced**: Git matches cluster
- **OutOfSync**: Git has changes not in cluster
- **Unknown**: Can't determine

## Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Loki](https://grafana.com/docs/loki/latest/)

## Support

### Check Application Status

```bash
# ArgoCD applications
kubectl get applications -n argocd

# Application resources
kubectl get all -n monitoring

# Events
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

### View Logs

```bash
# ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Application pod logs
kubectl logs -n monitoring <pod-name>
```

## Important Notes

### SSH Keys

- ⚠️ **NEVER commit SSH keys to this repository**
- Keys are gitignored
- Generate keys using the provided script
- Store private key in terraform repo secrets only

### Sync Timing

- ArgoCD polls Git every **3 minutes** by default
- Can force sync via UI or CLI
- Webhook support available for instant sync

### Resource Cleanup

When deleting applications:

- ArgoCD can auto-prune resources (if `prune: true`)
- Or manually delete resources before removing app definition

---

**Repository**: https://github.com/dareyio/gitops  
**Infrastructure Repo**: https://github.com/dareyio/terraform  
**Maintained By**: DevOps Team  
**Last Updated**: October 11, 2025
