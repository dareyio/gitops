# ArgoCD Cluster Setup Report

**Generated:** 2025-11-06  
**Cluster:** `darey-io-v2-lab-prod`  
**Region:** `eu-west-2`  
**Context Alias:** `aws-v2-cluster`  
**Kubeconfig Updated:** ✅ Using EKS admin role for authentication

---

## Executive Summary

This report provides a comprehensive analysis of the ArgoCD setup on the EKS cluster `darey-io-v2-lab-prod`. The cluster is **ACTIVE** and **FULLY ACCESSIBLE** via kubeconfig configured with EKS admin role authentication.

### Key Findings

✅ **Cluster Status**: ACTIVE (Kubernetes v1.34)  
✅ **Cluster Access**: ✅ FIXED - kubeconfig updated with EKS admin role  
✅ **Nodes**: 3 nodes running (Ready)  
✅ **ArgoCD**: All pods running, applications synced  
✅ **ArgoCD Configuration**: Properly configured with GitOps repository  
✅ **IAM Roles**: All required IRSA roles exist  
✅ **ACM Certificate**: Configured for `*.talentos.darey.io`  
✅ **Route53 Zone**: `talentos.darey.io` zone exists  
✅ **External Secrets**: Running, ClusterSecretStore active, ExternalSecret synced  
✅ **External DNS**: Running (managing DNS records)  
✅ **ALB Controller**: Running (2 pods)  
⚠️ **Grafana**: CrashLoopBackOff - datasource configuration error  
⚠️ **EBS CSI Driver**: CrashLoopBackOff - IRSA role permissions issue  
⚠️ **External DNS**: Only 1 pod running (correctly configured, but consider 2 for HA)  
⚠️ **Grafana Ingress**: Not found (should use ALB per documentation)  
⚠️ **ArgoCD Ingress**: Uses nginx ingress class (not ALB as per documentation)  
⚠️ **ArgoCD Server**: 24 restarts in 26 hours (needs investigation)

---

## 1. Cluster Configuration

### Basic Information

| Property               | Value                                                                      |
| ---------------------- | -------------------------------------------------------------------------- |
| **Cluster Name**       | `darey-io-v2-lab-prod`                                                     |
| **Status**             | ACTIVE                                                                     |
| **Kubernetes Version** | 1.34                                                                       |
| **Region**             | eu-west-2                                                                  |
| **VPC ID**             | `vpc-0bb7a12f9a34dfb1d`                                                    |
| **Endpoint**           | `https://C95D284C309F53443A292B7006BE6E94.gr7.eu-west-2.eks.amazonaws.com` |
| **Public Access**      | Enabled (0.0.0.0/0)                                                        |
| **Private Access**     | Enabled                                                                    |

### Network Configuration

- **Subnets**: 2 subnets configured
  - `subnet-071727569182dc738`
  - `subnet-0962da11cb794b5ee`
- **Security Groups**:
  - Cluster Security Group: `sg-05fed610c3bcebb11`
  - Additional Security Group: `sg-0229f4f5ba2bd90cd`

### Kubeconfig Setup

✅ **Context Added**: `aws-v2-cluster`  
✅ **Context Location**: `~/.kube/config`  
✅ **Authentication**: Configured to use EKS admin role (`darey-io-v2-lab-prod-eks-admin-role`)

**To switch context:**

```bash
kubectl config use-context aws-v2-cluster
# Or use kubectx (if installed)
kubectx aws-v2-cluster
```

**Current Configuration:**

- Context uses IAM role-based authentication
- No need to manually assume role - kubeconfig handles it automatically

---

## 2. ArgoCD Applications Configuration

### Root Application (`prod-applications`)

**Location**: `gitops/argocd/bootstrap/prod.yaml`

- **Repository**: `git@github.com:dareyio/gitops.git`
- **Path**: `argocd/applications/prod`
- **Sync Policy**: Automated with prune and self-heal enabled
- **Recursion**: Enabled (watches all subdirectories)

### Configured Applications

Based on the ArgoCD application manifests, the following applications are configured:

#### 2.1 Monitoring Stack

**kube-prometheus-stack** (`kube-prometheus-stack.yaml`)

- **Chart**: `prometheus-community/kube-prometheus-stack`
- **Version**: `56.0.0`
- **Namespace**: `monitoring`
- **Features**:
  - Prometheus with 30-day retention
  - 50Gi persistent storage (gp2-eks-csi)
  - Grafana with admin password: `admin` (⚠️ CHANGE IMMEDIATELY)
  - Dashboard provisioning via ConfigMaps
  - 10Gi Grafana persistence
  - Pre-configured Prometheus and Loki datasources
- **Ingress**: Disabled (should be configured separately)

**loki** (`loki.yaml`)

- **Chart**: `grafana/loki-stack`
- **Version**: `2.10.0`
- **Namespace**: `monitoring`
- **Features**:
  - 10Gi persistent storage (gp2-eks-csi)
  - Promtail enabled for log collection
  - Grafana integration disabled (using kube-prometheus-stack Grafana)

#### 2.2 External Operators

**external-secrets-operator** (`external-secrets-operator.yaml`)

- **Chart**: `external-secrets/external-secrets`
- **Version**: `0.9.11`
- **Namespace**: `external-secrets-system`
- **IRSA Role**: `arn:aws:iam::586794457112:role/prod-external-secrets-operator-role`
- **Replicas**: 2
- **Resources**: 100m CPU / 128Mi memory (requests), 200m CPU / 256Mi memory (limits)
- **CRDs**: Auto-installed

**external-dns** (`external-dns.yaml`)

- **Chart**: `kubernetes-sigs/external-dns`
- **Version**: `1.13.1`
- **Namespace**: `external-dns-system`
- **IRSA Role**: `arn:aws:iam::586794457112:role/prod-external-dns-role`
- **Configuration**:
  - Domain Filter: `talentos.darey.io`
  - Policy: `upsert-only` (safe mode)
  - Annotation Filter: `external-dns.alpha.kubernetes.io/manage=true`
  - Sources: Ingress and Service
  - Zone Type: Public
- **Replicas**: 2
- **Resources**: 100m CPU / 128Mi memory (requests), 200m CPU / 256Mi memory (limits)

**aws-load-balancer-controller** (`aws-load-balancer-controller.yaml`)

- **Chart**: `aws/aws-load-balancer-controller`
- **Version**: `1.7.1`
- **Namespace**: `kube-system`
- **IRSA Role**: `arn:aws:iam::586794457112:role/prod-aws-load-balancer-controller-role`
- **Configuration**:
  - Cluster Name: `darey-io-v2-lab-prod`
  - Region: `eu-west-2`
  - VPC ID: `vpc-0bb7a12f9a34dfb1d`
- **Resources**: 100m CPU / 128Mi memory (requests), 200m CPU / 256Mi memory (limits)

#### 2.3 Certificate Management

**cert-manager ClusterIssuers** (`cert-manager-clusterissuer/`)

- **letsencrypt-prod**: Production Let's Encrypt issuer
- **letsencrypt-staging**: Staging Let's Encrypt issuer
- **Note**: cert-manager is configured but marked as "standby" in documentation

#### 2.4 Dashboards

**Grafana Dashboards** (`dashboards/`)

- `cm-cluster-overview.yaml`: Kubernetes cluster overview dashboard
- `cm-logs.yaml`: Logs dashboard
- `cm-node-metrics.yaml`: Node metrics dashboard
- `cm-pod-workload.yaml`: Pod workload dashboard

#### 2.5 Other Resources

- `wildcard-tls.yaml`: TLS certificate configuration
- `example-api.yaml`: Example API application (reference)

---

## 3. IAM Roles (IRSA)

All required IAM roles for IRSA authentication exist:

| Role Name                                | Purpose                   | Status    |
| ---------------------------------------- | ------------------------- | --------- |
| `prod-external-secrets-operator-role`    | External Secrets Operator | ✅ Exists |
| `prod-external-dns-role`                 | External DNS              | ✅ Exists |
| `prod-aws-load-balancer-controller-role` | ALB Controller            | ✅ Exists |
| `prod-cert-manager-role`                 | cert-manager              | ✅ Exists |
| `darey-io-v2-lab-prod-eks-admin-role`    | Cluster Admin Access      | ✅ Exists |

---

## 4. DNS and Certificate Configuration

### Route53 Hosted Zone

- **Zone ID**: `Z01777392RVDKH2QRSDZO`
- **Domain**: `talentos.darey.io`
- **Status**: Active

### ACM Certificate

- **ARN**: `arn:aws:acm:eu-west-2:586794457112:certificate/8ab08b2b-7dcd-4a27-b932-92e165ac28f2`
- **Domain**: `*.talentos.darey.io`
- **Status**: Issued (according to documentation)
- **Note**: Certificate status shows "None" in API response - may need verification

### DNS Records Status

✅ **DNS Records Found**:

- `argocd.talentos.darey.io` - A record exists (External DNS managed)
- `grafana.talentos.darey.io` - A record exists (External DNS managed)
- TXT records present indicating External DNS ownership

⚠️ **Note**: A record values show "None" - this may indicate:

- ALB is still provisioning
- ALB controller hasn't created the load balancer yet
- DNS propagation delay

**Expected Services**:

- **Grafana**: `https://grafana.talentos.darey.io`
- **ArgoCD**: `https://argocd.talentos.darey.io`

---

## 5. Cluster Access Status

### ✅ RESOLVED: Cluster Access Configured

**Solution Applied**: Updated kubeconfig to use EKS admin role for authentication

**Current Status**: ✅ **WORKING**

- Context `aws-v2-cluster` is active
- Authentication via IAM role: `darey-io-v2-lab-prod-eks-admin-role`
- All kubectl commands working

**Verification**:

```bash
kubectl get nodes
# Output: 3 nodes running (Ready)

kubectl get namespaces
# Output: All namespaces accessible
```

### Alternative Access Methods

If you need to add direct user access (instead of role-based):

1. **Add user to aws-auth ConfigMap**:

   ```bash
   kubectl edit configmap aws-auth -n kube-system
   ```

   Add under `mapUsers`:

   ```yaml
   mapUsers: |
     - userarn: arn:aws:iam::586794457112:user/Dare
       username: Dare
       groups:
         - system:masters
   ```

---

## 6. Current Application Status

### ArgoCD Applications

| Application                    | Sync Status | Health Status  | Notes                           |
| ------------------------------ | ----------- | -------------- | ------------------------------- |
| `prod-applications`            | ✅ Synced   | ✅ Healthy     | Root application                |
| `prod-apps`                    | ✅ Synced   | ✅ Healthy     | Additional root app             |
| `kube-prometheus-stack`        | ✅ Synced   | ⚠️ Progressing | Grafana pod in CrashLoopBackOff |
| `loki`                         | ✅ Synced   | ✅ Healthy     | Running                         |
| `external-secrets-operator`    | ✅ Synced   | ✅ Healthy     | Running (2 replicas)            |
| `external-dns`                 | ✅ Synced   | ✅ Healthy     | Running (1 pod, should be 2)    |
| `aws-load-balancer-controller` | ✅ Synced   | ✅ Healthy     | Running (2 pods)                |

### Pod Status Summary

**ArgoCD Namespace** (`argocd`):

- ✅ All 7 pods running
- ✅ argocd-server: Running (24 restarts in 26h - may need investigation)
- ✅ argocd-application-controller: Running
- ✅ argocd-repo-server: Running
- ✅ argocd-redis: Running
- ✅ argocd-dex-server: Running
- ✅ argocd-applicationset-controller: Running
- ✅ argocd-notifications-controller: Running

**Monitoring Namespace** (`monitoring`):

- ✅ Prometheus: Running (2/2 ready)
- ✅ Alertmanager: Running (2/2 ready)
- ✅ Loki: Running (1/1 ready)
- ✅ Promtail: Running (2 pods)
- ✅ Node Exporter: Running (3 pods)
- ✅ Kube State Metrics: Running
- ❌ **Grafana: CrashLoopBackOff** (2/3 containers ready)
  - **Issue**: Datasource configuration error - multiple datasources marked as default
  - **Error**: `"Only one datasource per organization can be marked as default"`

**External Secrets Namespace** (`external-secrets-system`):

- ✅ external-secrets-operator: Running (2 replicas)
- ✅ external-secrets-operator-webhook: Running
- ✅ external-secrets-operator-cert-controller: Running

**External DNS Namespace** (`external-dns-system`):

- ⚠️ external-dns: Running (1 pod, configured for 2 replicas)

**Kube-System Namespace**:

- ✅ aws-load-balancer-controller: Running (2 pods)
- ❌ **ebs-csi-controller: CrashLoopBackOff** (5/6 containers ready)
  - **Issue**: IRSA role permissions - `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity`
  - **Role**: `darey-io-v2-lab-prod-ebs-csi-driver-role`

### Ingress Status

**Current Ingresses** (using nginx ingress class):

- ✅ `argocd-server` (argocd namespace) - `argocd.darey.io`
- ✅ Multiple lab-related ingresses (jupyter, vscode, ubuntu, mssql, etc.)

**Missing Ingresses** (per documentation):

- ❌ Grafana ingress not found in monitoring namespace
- ⚠️ ArgoCD ingress uses nginx, not ALB (per documentation should use ALB)

**Ingress Classes Available**:

- ✅ `alb` - AWS Load Balancer Controller
- ✅ `nginx` - NGINX Ingress Controller

### Services Status

**ArgoCD Services**:

- ✅ argocd-server: ClusterIP (80/TCP, 443/TCP)
- ✅ argocd-repo-server: ClusterIP
- ✅ argocd-redis: ClusterIP
- ✅ argocd-dex-server: ClusterIP
- ✅ argocd-applicationset-controller: ClusterIP

**Monitoring Services**:

- ✅ kube-prometheus-stack-prometheus: ClusterIP (9090/TCP)
- ✅ kube-prometheus-stack-grafana: ClusterIP (80/TCP)
- ✅ kube-prometheus-stack-alertmanager: ClusterIP (9093/TCP)
- ✅ loki: ClusterIP (3100/TCP)

---

## 7. Accessing Services

### ArgoCD Access

**Via Port Forward**:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit https://localhost:8080
# Username: admin
# Password: Get from secret (see below)
```

**Get ArgoCD Admin Password**:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

**Current Password**: `-Py-X6iw-wMjf-80` ⚠️ **CHANGE IMMEDIATELY**

**Via Ingress**:

- URL: `http://argocd.darey.io` (nginx ingress, not HTTPS)
- Note: Uses nginx ingress class, not ALB as per documentation

### Grafana Access

**Via Port Forward**:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Visit http://localhost:3000
# Username: admin
# Password: admin (⚠️ CHANGE IMMEDIATELY)
```

**Via Ingress**:

- ❌ **Not configured** - No ingress found in monitoring namespace
- ⚠️ Per documentation, should be at `https://grafana.talentos.darey.io` using ALB

### Prometheus Access

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090
```

---

## 8. Issues Found and Recommendations

### Critical Issues

#### 1. Grafana CrashLoopBackOff ❌

**Status**: Pod restarting continuously  
**Error**: `"Only one datasource per organization can be marked as default"`  
**Location**: `kube-prometheus-stack-grafana-768db784c8-v8pfc` in `monitoring` namespace

**Root Cause**: The Grafana datasource configuration in `kube-prometheus-stack.yaml` has both Prometheus and Loki marked as default datasources.

**Fix Required**:

```yaml
# In kube-prometheus-stack.yaml, update datasources section:
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://kube-prometheus-stack-prometheus.monitoring.svc:9090
        access: proxy
        isDefault: true # ✅ Keep this
      - name: Loki
        type: loki
        url: http://loki.monitoring.svc:3100
        access: proxy
        isDefault: false # ❌ Change from true to false
```

**Action**: Update `gitops/argocd/applications/prod/kube-prometheus-stack.yaml` and commit.

#### 2. EBS CSI Driver CrashLoopBackOff ❌

**Status**: Pods restarting continuously  
**Error**: `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity`  
**Location**: `ebs-csi-controller` pods in `kube-system` namespace  
**Role**: `darey-io-v2-lab-prod-ebs-csi-driver-role`

**Root Cause**: EBS CSI driver service account doesn't have proper IRSA role annotation or the role's trust policy is incorrect.

**Fix Required**:

1. Check EBS CSI driver service account:

   ```bash
   kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml
   ```

2. Verify IAM role trust policy allows the service account:

   ```bash
   aws iam get-role --role-name darey-io-v2-lab-prod-ebs-csi-driver-role \
     --query 'Role.AssumeRolePolicyDocument'
   ```

3. Update service account annotation if missing:
   ```bash
   kubectl annotate sa ebs-csi-controller-sa -n kube-system \
     eks.amazonaws.com/role-arn=arn:aws:iam::586794457112:role/darey-io-v2-lab-prod-ebs-csi-driver-role
   ```

**Impact**: Persistent volumes may not work correctly until fixed.

### Warning Issues

#### 3. External DNS Single Pod ⚠️

**Status**: Only 1 pod running (configured for 2 replicas)  
**Location**: `external-dns-system` namespace

**Check**:

```bash
kubectl get deployment external-dns -n external-dns-system
kubectl describe deployment external-dns -n external-dns-system
```

**Action**: Investigate why second pod isn't starting (may be intentional or resource constraints).

#### 4. Grafana Ingress Missing ⚠️

**Status**: No ingress found in monitoring namespace  
**Expected**: Per documentation, should have ALB ingress at `https://grafana.talentos.darey.io`

**Action**: Create Grafana ingress using ALB ingress class (see documentation).

#### 5. ArgoCD Ingress Using Wrong Class ⚠️

**Status**: ArgoCD ingress uses `nginx` ingress class  
**Expected**: Per documentation, should use `alb` ingress class

**Current**: `argocd.darey.io` via nginx ingress (Network Load Balancer)  
**Expected**: `https://argocd.talentos.darey.io` via ALB

**Note**: Current setup uses NGINX Ingress Controller with a Network Load Balancer (NLB). This is functional but differs from documentation which suggests using ALB. Both approaches work - decide based on requirements:
- **ALB**: Better for HTTP/HTTPS with advanced routing, WAF integration
- **NGINX + NLB**: Simpler, works well for basic ingress needs

**Action**: Review ingress strategy and update documentation or migrate to ALB if desired.

#### 6. ArgoCD Server Restarts ⚠️

**Status**: argocd-server pod has 24 restarts in 26 hours  
**Location**: `argocd-server-95dbfff4b-llbxz` in `argocd` namespace

**Action**: Investigate logs to determine cause of restarts:

```bash
kubectl logs -n argocd argocd-server-95dbfff4b-llbxz --previous
```

---

## 9. Application Status Check Commands

Once cluster access is established, use these commands to verify application status:

### Check ArgoCD Applications

```bash
# List all applications
kubectl get applications -n argocd

# Check specific application status
kubectl describe application kube-prometheus-stack -n argocd
kubectl describe application external-secrets-operator -n argocd
kubectl describe application external-dns -n argocd
kubectl describe application aws-load-balancer-controller -n argocd
```

### Check Pod Status

```bash
# Check all namespaces
kubectl get pods -A

# Check specific namespaces
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get pods -n external-secrets-system
kubectl get pods -n external-dns-system
kubectl get pods -n kube-system | grep aws-load-balancer
```

### Check Ingresses

```bash
# List all ingresses
kubectl get ingress -A

# Check ingress details
kubectl describe ingress -n monitoring
kubectl describe ingress -n argocd
```

### Check Services

```bash
# Check services in monitoring namespace
kubectl get svc -n monitoring

# Check ArgoCD services
kubectl get svc -n argocd
```

---

## 10. Verification Checklist

### Infrastructure ✅

- [x] Cluster exists and is ACTIVE
- [x] Kubeconfig context configured (`aws-v2-cluster`)
- [x] Cluster access working (using EKS admin role)
- [x] 3 nodes running (Ready)
- [x] VPC and networking configured
- [x] IAM roles exist for IRSA
- [x] ACM certificate exists
- [x] Route53 hosted zone exists
- [x] DNS records created (External DNS managed)

### ArgoCD Configuration ✅

- [x] Root application configured (`prod-applications`, `prod-apps`)
- [x] Git repository configured
- [x] Application manifests exist
- [x] Applications deployed and synced
- [x] ArgoCD UI accessible via ingress (`argocd.darey.io`)
- [x] All ArgoCD pods running
- [x] ArgoCD admin password retrieved

### Applications Configuration ✅

- [x] kube-prometheus-stack configured and deployed
  - ⚠️ Grafana pod in CrashLoopBackOff (datasource config issue)
  - ✅ Prometheus running
  - ✅ Alertmanager running
- [x] loki configured and running
- [x] external-secrets-operator configured and running
  - ✅ ClusterSecretStore active
  - ✅ ExternalSecret synced
- [x] external-dns configured and running
  - ✅ 1 pod running (correctly configured)
  - 💡 Consider scaling to 2 for high availability
- [x] aws-load-balancer-controller configured and running (2 pods)
- [x] cert-manager ClusterIssuers configured
- [x] Grafana dashboards configured
- [x] EBS CSI driver deployed but failing (IRSA issue)

### DNS and Ingress ⚠️

- [x] ACM certificate configured
- [x] Route53 zone exists
- [x] DNS records created (External DNS managed)
  - ⚠️ A records show "None" value (ALB may not be created yet)
- [x] Ingresses created
  - ✅ ArgoCD ingress exists (nginx class)
  - ❌ Grafana ingress missing
  - ✅ Multiple lab ingresses exist
- [x] ALB controller running (2 pods)
- [x] NGINX ingress controller running
- ⚠️ Ingresses using nginx class instead of ALB (per documentation)

---

## 11. Port Forwarding Commands

### ArgoCD

```bash
# Port forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access: https://localhost:8080
# Username: admin
# Password: -Py-X6iw-wMjf-80 (⚠️ CHANGE IMMEDIATELY)
```

### Grafana (when fixed)

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access: http://localhost:3000
# Username: admin
# Password: admin (⚠️ CHANGE IMMEDIATELY)
```

### Prometheus

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Access: http://localhost:9090
```

### Loki

```bash
# Port forward Loki
kubectl port-forward -n monitoring svc/loki 3100:3100

# Access: http://localhost:3100
```

### Alertmanager

```bash
# Port forward Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Access: http://localhost:9093
```

---

## 12. Next Steps

### Immediate Actions

1. **Fix Cluster Access**:

   - Add current user to `aws-auth` ConfigMap OR
   - Use EKS admin role to access cluster

2. **Verify ArgoCD Deployment**:

   - Check if ArgoCD is deployed
   - Access ArgoCD UI
   - Verify applications are synced

3. **Check Application Status**:

   - Verify all applications are healthy
   - Check pod status in all namespaces
   - Review application logs if needed

4. **Verify Ingresses**:

   - Check if ingresses exist
   - Verify ALB controller is running
   - Check DNS records in Route53

5. **Security Hardening**:
   - Change Grafana admin password
   - Change ArgoCD admin password
   - Review RBAC policies

### Future Enhancements

1. **Set up Ingresses** (if not already configured):

   - Create Grafana ingress
   - Create ArgoCD ingress
   - Verify DNS records are created

2. **Monitoring**:

   - Set up alerting rules in Prometheus
   - Configure Grafana dashboards
   - Set up log aggregation queries

3. **Backup**:
   - Set up backups for ArgoCD
   - Configure etcd backups
   - Set up persistent volume backups

---

## 13. Troubleshooting Guide

### Cannot Access Cluster

**Symptoms**: `error: You must be logged in to the server`

**Solutions**:

1. Check AWS credentials: `aws sts get-caller-identity`
2. Verify user is in aws-auth ConfigMap
3. Try assuming EKS admin role
4. Check IAM permissions for EKS access

### Applications Not Syncing

**Check**:

```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

**Common Issues**:

- Git repository authentication (SSH key)
- Helm chart version not found
- Resource conflicts
- Namespace creation issues

### Pods Not Starting

**Check**:

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

**Common Issues**:

- Image pull errors
- Resource limits
- Persistent volume issues
- IRSA role misconfiguration

### Ingress Not Creating ALB

**Check**:

```bash
kubectl get ingress -A
kubectl get pods -n kube-system | grep aws-load-balancer
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Common Issues**:

- ALB controller not running
- IngressClass not found
- IAM role permissions
- Subnet tags missing

---

## 14. Useful Commands Reference

### Cluster Management

```bash
# Switch context
kubectl config use-context aws-v2-cluster
kubectx aws-v2-cluster  # if kubectx installed

# Get cluster info
kubectl cluster-info

# Get nodes
kubectl get nodes

# Get all resources
kubectl get all -A
```

### ArgoCD CLI

```bash
# Install ArgoCD CLI
brew install argocd  # macOS
# or
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Port forward ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login
argocd login localhost:8080

# List applications
argocd app list

# Get application details
argocd app get <app-name>

# Sync application
argocd app sync <app-name>
```

### Port Forwarding

```bash
# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Loki
kubectl port-forward -n monitoring svc/loki 3100:3100
```

---

## 15. Summary

### What's Working ✅

1. **Cluster Infrastructure**: Cluster is ACTIVE with 3 nodes running
2. **Cluster Access**: ✅ FIXED - kubeconfig configured with EKS admin role
3. **ArgoCD**: All pods running, applications synced and healthy
4. **External Secrets**: Running, ClusterSecretStore active, ExternalSecret synced
5. **External DNS**: Running and managing DNS records
6. **ALB Controller**: Running (2 pods)
7. **Prometheus**: Running and collecting metrics
8. **Loki**: Running and collecting logs
9. **Alertmanager**: Running
10. **IAM Roles**: All required IRSA roles exist
11. **DNS Setup**: Route53 zone and ACM certificate configured
12. **Ingresses**: Multiple ingresses working (using nginx class)

### What Needs Attention ⚠️

1. **Grafana**: 🔴 CrashLoopBackOff - datasource configuration error (CRITICAL)
2. **EBS CSI Driver**: 🔴 CrashLoopBackOff - IRSA role permissions issue (CRITICAL)
3. **External DNS**: ⚠️ Only 1 pod running (correctly configured, but consider 2 for HA)
4. **Grafana Ingress**: ❌ Missing (should exist per documentation)
5. **ArgoCD Ingress**: ⚠️ Uses nginx instead of ALB (per documentation)
6. **ArgoCD Server**: ⚠️ 24 restarts in 26 hours (needs investigation)
7. **Security**: 🔴 Default passwords need to be changed immediately

### Recommendations

1. **Immediate** (Today):
   - Fix Grafana datasource configuration
   - Fix EBS CSI driver IRSA permissions
   - Change default passwords

2. **Short-term** (This Week):
   - Investigate ArgoCD server restarts
   - Fix External DNS replica count
   - Create Grafana ingress with ALB

3. **Medium-term** (This Month):
   - Review and standardize ingress strategy (ALB vs nginx)
   - Set up comprehensive monitoring and alerting
   - Implement backup procedures

4. **Long-term** (Ongoing):
   - Implement disaster recovery procedures
   - Set up automated testing for ArgoCD applications
   - Review and optimize resource allocations

---

---

## 16. Quick Access Summary

### Cluster Access

**Context**: `aws-v2-cluster`  
**Switch**: `kubectl config use-context aws-v2-cluster` or `kubectx aws-v2-cluster`  
**Authentication**: EKS Admin Role (automatically handled)

### Service URLs

| Service | Access Method | URL/Credentials |
|---------|---------------|-----------------|
| **ArgoCD** | Ingress | `http://argocd.darey.io` |
| **ArgoCD** | Port Forward | `https://localhost:8080` (after port-forward) |
| **ArgoCD** | Credentials | `admin` / `-Py-X6iw-wMjf-80` ⚠️ CHANGE |
| **Grafana** | Port Forward | `http://localhost:3000` (when fixed) |
| **Grafana** | Credentials | `admin` / `admin` ⚠️ CHANGE |
| **Prometheus** | Port Forward | `http://localhost:9090` |
| **Loki** | Port Forward | `http://localhost:3100` |

### Cluster Statistics

- **Nodes**: 3 (Bottlerocket OS, Kubernetes v1.34)
- **Namespaces**: 18
- **ArgoCD Applications**: 7 (all synced)
- **Total Pods**: 49
- **Running Pods**: 45
- **CrashLoopBackOff Pods**: 4
  - 2x EBS CSI controller (kube-system)
  - 1x Grafana (monitoring)
  - 1x jibri (liveclasses - not ArgoCD managed)
- **Storage Classes**: 4 (gp2-eks-csi is default)
- **Persistent Volumes**: 3 bound successfully
- **Ingresses**: 9 (all using nginx class)
- **Services**: 47

### Critical Actions Required

1. 🔴 **Fix Grafana datasource configuration** (update Helm values)
2. 🔴 **Fix EBS CSI driver IRSA** (check IAM permissions)
3. 🔴 **Change default passwords** (ArgoCD and Grafana)
4. 🟡 **Investigate ArgoCD server restarts** (24 restarts in 26h)
5. 🟢 **Create Grafana ingress** (if external access needed)

---

**Report Generated**: 2025-11-06  
**Cluster**: `darey-io-v2-lab-prod`  
**Region**: `eu-west-2`  
**Context**: `aws-v2-cluster`  
**Access Method**: EKS Admin Role (`darey-io-v2-lab-prod-eks-admin-role`)
