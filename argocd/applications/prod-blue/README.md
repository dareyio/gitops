# Production Applications - GitOps Configuration

This directory contains ArgoCD application manifests for production workloads, including monitoring, ingress, and external operators.

---

## 📋 Quick Navigation

- [Deployed Applications](#deployed-applications)
- [Adding New Services](#quick-guide-expose-a-new-service)
- [Certificate Strategy](#certificate-management)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)

---

## 🚀 Deployed Applications

### **Monitoring Stack**
- **Prometheus + Grafana**: `kube-prometheus-stack.yaml`
  - URL: https://grafana.talentos.darey.io
  - Metrics collection, alerting, visualization
  
- **Loki**: `loki.yaml`
  - Log aggregation and querying

### **GitOps & CI/CD**
- **ArgoCD**: Deployed via Terraform
  - URL: https://argocd.talentos.darey.io
  - GitOps continuous delivery

### **External Operators**
- **External Secrets Operator**: `external-secrets-operator.yaml`
  - Syncs secrets from AWS Secrets Manager
  - IRSA authentication (no access keys)
  - ClusterSecretStore: `aws-secrets-manager`
  - Example: `external-secrets-example.yaml`

- **External DNS**: `external-dns.yaml`
  - Automatic Route53 DNS record management
  - Policy: `upsert-only` (safe mode)
  - Only manages resources with annotation: `external-dns.alpha.kubernetes.io/manage: "true"`

- **AWS Load Balancer Controller**: `aws-load-balancer-controller.yaml`
  - Provisions ALB for ingress resources
  - Manages target groups and listeners
  - Integrated with ACM for TLS

### **Ingress Resources**
- **Grafana Ingress**: `grafana-ingress.yaml`
  - ALB with ACM certificate
  - Automatic HTTPS with HTTP redirect
  
- **ArgoCD Ingress**: `argocd-ingress.yaml`
  - ALB with ACM certificate  
  - HTTPS backend (ArgoCD uses TLS)
  - gRPC support for CLI

---

## 🎯 Certificate Management

### **Strategy: ACM + ALB (Primary)**

**What We Use:**
- **ACM Wildcard Certificate**: `*.talentos.darey.io` + `talentos.darey.io`
- **Managed By**: Terraform (`terraform/modules/acm-certificate/`)
- **Validation**: DNS (automatic via Route53)
- **Cost**: FREE
- **Renewal**: Automatic by AWS (13 months validity)

**Why ACM + ALB:**
- ✅ TLS termination at ALB (outside cluster)
- ✅ Private keys never exposed
- ✅ AWS-native, highly reliable
- ✅ CloudWatch metrics included
- ✅ One cert for all subdomains

**cert-manager**: Installed but inactive (standby for future internal services)

### **When to Use What**

| Use Case | Solution | IngressClass |
|----------|----------|--------------|
| External service (internet) | ACM + ALB | `alb` |
| Internal service (future) | cert-manager | `nginx` |
| Service mesh (future) | cert-manager | - |

---

## 🚀 Quick Guide: Expose a New Service

### **Step 1: Get Certificate ARN**
```bash
# Certificate ARN (already created):
arn:aws:acm:eu-west-2:586794457112:certificate/8ab08b2b-7dcd-4a27-b932-92e165ac28f2
```

### **Step 2: Create Ingress**

Create `[service-name]-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-west-2:586794457112:certificate/8ab08b2b-7dcd-4a27-b932-92e165ac28f2
    external-dns.alpha.kubernetes.io/hostname: myapp.talentos.darey.io
    external-dns.alpha.kubernetes.io/manage: "true"
spec:
  ingressClassName: alb
  rules:
  - host: myapp.talentos.darey.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
```

### **Step 3: Deploy**
```bash
cd gitops
git add argocd/applications/prod/myapp-ingress.yaml
git commit -m "feat: add ingress for myapp"
git push origin main
# ArgoCD syncs automatically
```

### **Step 4: Verify**
```bash
kubectl get ingress -n [namespace]
dig myapp.talentos.darey.io
curl https://myapp.talentos.darey.io
```

---

## 🔧 Common Annotations

### **Backend Protocol**
```yaml
alb.ingress.kubernetes.io/backend-protocol: HTTP   # Default
alb.ingress.kubernetes.io/backend-protocol: HTTPS  # For ArgoCD, secure services
```

### **Health Checks**
```yaml
alb.ingress.kubernetes.io/healthcheck-path: /health
alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
```

### **Security**
```yaml
alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:...  # Optional WAF
alb.ingress.kubernetes.io/inbound-cidrs: 1.2.3.4/32         # IP allowlist
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Internet (Users)                        │
└─────────────────────┬───────────────────────────────────────┘
                      │ HTTPS (TLS 1.2/1.3)
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  AWS Application Load Balancer               │
│  - TLS Termination (ACM Certificate)                        │
│  - HTTP → HTTPS Redirect                                    │
│  - Health Checks                                            │
│  - CloudWatch Metrics                                       │
└─────────────────────┬───────────────────────────────────────┘
                      │ HTTP (internal)
                      ▼
┌─────────────────────────────────────────────────────────────┐
│               Kubernetes Cluster (EKS)                       │
│                                                              │
│  Ingress Controller: AWS Load Balancer Controller           │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │   Grafana    │  │   ArgoCD     │                        │
│  │   Service    │  │   Service    │                        │
│  └──────────────┘  └──────────────┘                        │
│         │                  │                                 │
│         ▼                  ▼                                 │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │ Grafana Pods │  │ ArgoCD Pods  │                        │
│  └──────────────┘  └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘

External Integrations:
- Route53: DNS records (managed by External DNS)
- AWS Secrets Manager: Secrets (synced by External Secrets)
- ACM: TLS certificates (used by ALB)
```

---

## 🔐 IRSA Authentication (External Operators)

All external operators use **IAM Roles for Service Accounts (IRSA)** for AWS authentication:

### **How It Works**

1. **Service Account** annotated with IAM role ARN
2. **EKS** injects JWT token into pod
3. **Pod** calls AWS STS with JWT token
4. **AWS STS** validates token and returns temp credentials
5. **Operator** uses credentials to access AWS services

### **Operators Using IRSA**

| Operator | Service Account | IAM Role | AWS Service |
|----------|----------------|----------|-------------|
| External Secrets | `external-secrets-operator` | `prod-external-secrets-operator-role` | Secrets Manager |
| External DNS | `external-dns` | `prod-external-dns-role` | Route53 |
| ALB Controller | `aws-load-balancer-controller` | `prod-aws-load-balancer-controller-role` | ELB, EC2 |

**Benefits:**
- ✅ No long-lived access keys
- ✅ Automatic credential rotation
- ✅ Fine-grained permissions per operator
- ✅ CloudTrail audit trail

For detailed IRSA explanation, see: `gitops/argocd/applications/dev/README.md`

---

## 📊 DNS Management

### **External DNS Configuration**

- **Domain**: `talentos.darey.io`
- **Policy**: `upsert-only` (won't delete existing records)
- **Filter**: Only manages resources with `external-dns.alpha.kubernetes.io/manage: "true"`

### **How to Enable DNS for Ingress**

Add annotations to your ingress:
```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: myapp.talentos.darey.io
  external-dns.alpha.kubernetes.io/manage: "true"
```

External DNS will automatically create Route53 A record pointing to the ALB.

---

## 🔍 Troubleshooting

### **Ingress Not Creating ALB**

**Issue**: IngressClass 'alb' not found

**Solution**:
```bash
# Check if ALB controller is running
kubectl get pods -n kube-system | grep aws-load-balancer

# Check IngressClass
kubectl get ingressclass

# If missing, apply Terraform to create IAM role, then deploy ALB controller
```

### **External Secrets Not Syncing**

**Issue**: "could not get secret data from provider"

**Check**:
```bash
# Verify ClusterSecretStore
kubectl get clustersecretstore

# Check operator logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# Verify IAM role trust policy matches service account
```

**Common Issues**:
- Service account namespace mismatch in IAM trust policy
- IAM role missing Secrets Manager permissions
- Secret doesn't exist in AWS Secrets Manager

### **External DNS Not Creating Records**

**Issue**: DNS records not appearing in Route53

**Check**:
```bash
# Check External DNS logs
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns

# Verify ingress has correct annotations
kubectl get ingress [name] -n [namespace] -o yaml | grep external-dns
```

**Common Issues**:
- Missing `external-dns.alpha.kubernetes.io/manage: "true"` annotation
- IAM role missing Route53 permissions
- Domain not matching filter (`talentos.darey.io`)

### **Certificate Not Working**

**Issue**: HTTPS not working or certificate invalid

**Check**:
```bash
# Verify certificate status
aws acm describe-certificate --certificate-arn [ARN] --region eu-west-2

# Should show Status: ISSUED
```

**If PENDING_VALIDATION**:
```bash
# Check DNS validation records
aws route53 list-resource-record-sets --hosted-zone-id [ZONE_ID] | grep _acm
```

---

## 📋 Useful Commands

### **Certificates**
```bash
# Get ACM certificate ARN
terraform output acm_certificate_arn

# Check certificate status
aws acm describe-certificate --certificate-arn [ARN] --region eu-west-2
```

### **Ingresses**
```bash
# List all ingresses
kubectl get ingress -A

# Get ALB DNS
kubectl get ingress [name] -n [namespace] -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Check ingress details
kubectl describe ingress [name] -n [namespace]
```

### **External DNS**
```bash
# Check logs
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns --tail=50

# List Route53 records
aws route53 list-resource-record-sets --hosted-zone-id [ZONE_ID]
```

### **External Secrets**
```bash
# Check ClusterSecretStore
kubectl get clustersecretstore

# Check ExternalSecrets
kubectl get externalsecret -A

# View synced secret
kubectl get secret [name] -n [namespace] -o yaml
```

### **ALB Controller**
```bash
# Check controller pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## 🔐 Security Best Practices

### **TLS/HTTPS**
- ✅ All external services use HTTPS
- ✅ HTTP automatically redirects to HTTPS
- ✅ TLS 1.2 and TLS 1.3 support
- ✅ ACM manages certificate renewal

### **Authentication**
- ✅ IRSA for all AWS integrations (no access keys)
- ✅ Service account isolation per operator
- ✅ Fine-grained IAM policies

### **DNS Safety**
- ✅ External DNS uses `upsert-only` policy
- ✅ Annotation filter prevents accidental overwrites
- ✅ Only manages explicitly tagged resources

### **Network Security**
- ✅ ALB security groups auto-managed
- ✅ Pod security contexts enforced
- ✅ TLS termination at ALB (offload from pods)

---

## 📚 External Resources & Documentation

### **AWS Services**
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ACM Documentation](https://docs.aws.amazon.com/acm/)
- [Route53 Documentation](https://docs.aws.amazon.com/route53/)

### **Kubernetes Operators**
- [External Secrets Operator](https://external-secrets.io/)
- [External DNS](https://github.com/kubernetes-sigs/external-dns)
- [cert-manager](https://cert-manager.io/) (standby)

### **Monitoring**
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana](https://grafana.com/docs/)
- [Loki](https://grafana.com/docs/loki/)

---

## 🎯 Current Status

| Component | Status | Details |
|-----------|--------|---------|
| ACM Certificate | ✅ Issued | `*.talentos.darey.io` |
| ALB Controller | ⏳ Deploying | Requires IAM role via Terraform |
| External DNS | ✅ Running | Managing `talentos.darey.io` |
| External Secrets | ✅ Running | Syncing from Secrets Manager |
| Grafana Ingress | ⏳ Pending | Waiting for ALB controller |
| ArgoCD Ingress | ⏳ Pending | Waiting for ALB controller |

---

## 🚦 Next Steps

### **Immediate Actions Needed**

1. **Apply Terraform** to create AWS Load Balancer Controller IAM role
   ```bash
   cd terraform
   terraform plan --var-file=environments/prod/terraform.tfvars
   # Review and apply
   ```

2. **Update ALB Controller Manifest** with IAM role ARN
   ```bash
   terraform output aws_load_balancer_controller_role_arn
   # Update line 22 in aws-load-balancer-controller.yaml
   ```

3. **Deploy ALB Controller**
   ```bash
   cd gitops
   git add argocd/applications/prod/aws-load-balancer-controller.yaml
   git commit -m "feat: deploy AWS Load Balancer Controller"
   git push origin main
   ```

4. **Wait for ALB Provisioning** (2-3 minutes)
   ```bash
   kubectl get ingress -A
   # ADDRESS field will populate with ALB DNS
   ```

5. **Verify DNS** (5-10 minutes for propagation)
   ```bash
   dig grafana.talentos.darey.io
   dig argocd.talentos.darey.io
   ```

6. **Access Services**
   - https://grafana.talentos.darey.io
   - https://argocd.talentos.darey.io

---

## 📖 Reference Information

### **Cluster Details**
- **Name**: `darey-io-v2-lab-prod`
- **Region**: `eu-west-2`
- **VPC**: `vpc-0bb7a12f9a34dfb1d`
- **Domain**: `talentos.darey.io`

### **ACM Certificate**
- **ARN**: `arn:aws:acm:eu-west-2:586794457112:certificate/8ab08b2b-7dcd-4a27-b932-92e165ac28f2`
- **Domains**: `*.talentos.darey.io`, `talentos.darey.io`
- **Status**: Issued and validated

### **IAM Roles** (Managed by Terraform)
- External Secrets: `prod-external-secrets-operator-role`
- External DNS: `prod-external-dns-role`
- ALB Controller: `prod-aws-load-balancer-controller-role`

---

*Last Updated: October 2024*  
*Environment: Production*  
*Cluster: darey-io-v2-lab-prod*  
*Region: eu-west-2*

