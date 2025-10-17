# ALB Ingress Setup with ACM Certificate

This guide explains how to set up ALB ingresses for Grafana and ArgoCD using AWS Certificate Manager (ACM) for TLS termination and External DNS for automatic DNS record management.

## 📋 Overview

We're exposing two services via ALB:
- **Grafana**: `grafana.talentos.darey.io`
- **ArgoCD**: `argocd.talentos.darey.io`

### Architecture

```
Internet
    ↓
AWS ALB (with ACM certificate)
    ↓
Kubernetes Ingress (alb controller - EKS Auto Mode)
    ↓
Services (Grafana, ArgoCD)
    ↓
Pods
```

---

## 🚀 Setup Steps

### Step 1: Apply Terraform Changes

The ACM certificate will be created via Terraform.

```bash
cd terraform

# Initialize and plan
terraform init
terraform plan --var-file=environments/prod/terraform.tfvars

# Apply (only if you're authorized - user said they handle apply)
# This will create:
# - ACM wildcard certificate (*.talentos.darey.io)
# - DNS validation records in Route53
# - Wait for certificate validation
```

### Step 2: Get the Certificate ARN

After Terraform apply completes:

```bash
cd terraform
terraform output acm_certificate_arn
```

You'll get output like:
```
arn:aws:acm:eu-west-2:586794457112:certificate/abc123def456...
```

### Step 3: Update Ingress Manifests

Update both ingress files with the certificate ARN:

**grafana-ingress.yaml:**
```yaml
annotations:
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-west-2:586794457112:certificate/YOUR_CERT_ID
```

**argocd-ingress.yaml:**
```yaml
annotations:
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-west-2:586794457112:certificate/YOUR_CERT_ID
```

### Step 4: Commit and Push to GitOps Repo

```bash
cd gitops
git add argocd/applications/prod/grafana-ingress.yaml
git add argocd/applications/prod/argocd-ingress.yaml
git commit -m "feat: add ALB ingresses for Grafana and ArgoCD with ACM"
git push origin main
```

### Step 5: ArgoCD Auto-Sync

ArgoCD will automatically:
1. Detect the new ingress resources
2. Apply them to the cluster
3. EKS Auto Mode will create an ALB
4. External DNS will create Route53 A records

### Step 6: Verify ALB Creation

```bash
# Check ingress status
kubectl get ingress -n monitoring
kubectl get ingress -n argocd

# Check ALB details
kubectl describe ingress grafana-ingress -n monitoring
kubectl describe ingress argocd-server-ingress -n argocd

# Get ALB DNS name
kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Step 7: Verify DNS Records

```bash
# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id $(terraform output -raw route53_zone_id) --query "ResourceRecordSets[?Name=='grafana.talentos.darey.io.']"
aws route53 list-resource-record-sets --hosted-zone-id $(terraform output -raw route53_zone_id) --query "ResourceRecordSets[?Name=='argocd.talentos.darey.io.']"

# Or use dig/nslookup
dig grafana.talentos.darey.io
dig argocd.talentos.darey.io
```

### Step 8: Access the Services

Once DNS propagates (typically 1-5 minutes):

- **Grafana**: https://grafana.talentos.darey.io
- **ArgoCD**: https://argocd.talentos.darey.io

---

## 🔧 Configuration Details

### ACM Certificate

- **Type**: Wildcard certificate
- **Domains**: `*.talentos.darey.io`, `talentos.darey.io`
- **Validation**: DNS (automatic via Route53)
- **Validity**: 13 months (auto-renewed by AWS)
- **Cost**: FREE (for use with AWS services)

### ALB Configuration

Both ingresses use these common settings:

```yaml
annotations:
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
  alb.ingress.kubernetes.io/ssl-redirect: "443"
```

**Key Features:**
- `scheme: internet-facing` - Public ALB
- `target-type: ip` - Direct pod IPs (no NodePort needed)
- HTTP → HTTPS redirect
- ACM certificate for TLS termination

### Grafana-Specific Settings

```yaml
alb.ingress.kubernetes.io/backend-protocol: HTTP
alb.ingress.kubernetes.io/healthcheck-path: /api/health
```

- Backend uses HTTP (ALB terminates TLS)
- Health check on Grafana's health endpoint

### ArgoCD-Specific Settings

```yaml
alb.ingress.kubernetes.io/backend-protocol: HTTPS
alb.ingress.kubernetes.io/healthcheck-path: /healthz
alb.ingress.kubernetes.io/healthcheck-protocol: HTTPS
```

- Backend uses HTTPS (ArgoCD server uses TLS)
- Health check on ArgoCD's health endpoint
- Supports gRPC for ArgoCD CLI

### External DNS Configuration

```yaml
external-dns.alpha.kubernetes.io/hostname: grafana.talentos.darey.io
external-dns.alpha.kubernetes.io/manage: "true"
```

**What External DNS does:**
1. Watches for new ingresses
2. Creates Route53 A records pointing to ALB
3. Updates records when ALB changes
4. Cleans up records when ingress is deleted

**Safety:** 
- Only manages records with `manage: "true"` annotation
- Uses `upsert-only` policy (doesn't delete existing records)
- Won't interfere with manually created DNS records

---

## 🔍 Troubleshooting

### Ingress Not Creating ALB

**Check EKS Auto Mode status:**
```bash
kubectl get pods -n kube-system | grep alb
```

**Check ingress events:**
```bash
kubectl describe ingress grafana-ingress -n monitoring
kubectl describe ingress argocd-server-ingress -n argocd
```

**Common issues:**
- Certificate ARN not set or incorrect
- IngressClass `alb` not available
- EKS Auto Mode not enabled

### Certificate Not Validating

**Check certificate status:**
```bash
cd terraform
terraform output acm_certificate_status
```

Should show: `ISSUED`

If stuck in `PENDING_VALIDATION`:
```bash
# Check DNS validation records
aws acm describe-certificate --certificate-arn $(terraform output -raw acm_certificate_arn)

# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id $(terraform output -raw route53_zone_id) | grep _acm
```

### DNS Not Resolving

**Check External DNS logs:**
```bash
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns --tail=50
```

**Check Route53 records:**
```bash
aws route53 list-resource-record-sets --hosted-zone-id $(terraform output -raw route53_zone_id)
```

**Common issues:**
- External DNS not running
- IAM role permissions missing
- Annotation `manage: "true"` missing
- DNS propagation delay (wait 5-10 minutes)

### Services Not Accessible

**Check ALB target health:**
```bash
# Get ALB ARN from ingress
kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/load-balancer-name}'

# Check target group health (via AWS Console or CLI)
aws elbv2 describe-target-health --target-group-arn [TARGET_GROUP_ARN]
```

**Check pod status:**
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
```

**Check service endpoints:**
```bash
kubectl get endpoints -n monitoring kube-prometheus-stack-grafana
kubectl get endpoints -n argocd argocd-server
```

### ArgoCD gRPC Issues

If ArgoCD CLI doesn't work:

```bash
# Check if gRPC condition is applied
kubectl get ingress argocd-server-ingress -n argocd -o yaml | grep grpc

# Verify backend protocol
kubectl get ingress argocd-server-ingress -n argocd -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/backend-protocol}'
```

Should show: `HTTPS`

---

## 🔐 Security Considerations

### TLS/SSL

- ACM certificate provides TLS 1.2 and TLS 1.3
- Private key never leaves AWS infrastructure
- Automatic certificate renewal
- ALB terminates TLS (offloads encryption from pods)

### Security Groups

- ALB creates security groups automatically
- Allows inbound: 80, 443 from 0.0.0.0/0
- Allows outbound to EKS pods only
- Pod security groups managed by EKS

### Access Control

**Grafana:**
- Configure authentication in Grafana settings
- Consider OAuth/SAML integration
- Use strong admin password

**ArgoCD:**
- Already configured with SSO/RBAC
- Access via ArgoCD admin account
- Consider GitHub/GitLab OAuth

### Best Practices

1. **Enable WAF** (optional):
   ```yaml
   alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:...
   ```

2. **IP Allowlisting** (if needed):
   ```yaml
   alb.ingress.kubernetes.io/inbound-cidrs: 1.2.3.4/32,5.6.7.8/32
   ```

3. **SSL Policy**:
   ```yaml
   alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-2017-01
   ```

---

## 📊 Monitoring

### CloudWatch Metrics

ALB automatically sends metrics to CloudWatch:
- Request count
- Target response time
- HTTP 4xx/5xx errors
- Active connections

**View metrics:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=[ALB_NAME] \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### ALB Access Logs (Optional)

Enable access logs to S3:
```yaml
alb.ingress.kubernetes.io/load-balancer-attributes: access_logs.s3.enabled=true,access_logs.s3.bucket=my-alb-logs,access_logs.s3.prefix=grafana
```

### External DNS Logs

```bash
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns -f
```

---

## 🔄 Updating Ingresses

To update ingress configuration:

1. Edit the YAML file in GitOps repo
2. Commit and push changes
3. ArgoCD automatically applies changes
4. ALB updates (typically < 1 minute)

**Example: Add WAF:**
```yaml
annotations:
  alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:eu-west-2:586794457112:global/webacl/my-waf/abc123
```

---

## 📚 Additional Resources

- [EKS Auto Mode ALB Documentation](../../../terraform/modules/eks-cluster/EKS_AUTO_MODE_ALB.md)
- [AWS Load Balancer Controller Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
- [External DNS AWS Provider](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)
- [ACM Certificate Documentation](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)

---

## ✅ Verification Checklist

- [ ] ACM certificate created and validated (status: ISSUED)
- [ ] Certificate ARN added to ingress manifests
- [ ] Ingress manifests committed to GitOps repo
- [ ] ArgoCD synced the ingresses
- [ ] ALB created successfully
- [ ] External DNS created Route53 A records
- [ ] DNS resolves to ALB
- [ ] HTTPS works with valid certificate
- [ ] HTTP redirects to HTTPS
- [ ] Grafana accessible at https://grafana.talentos.darey.io
- [ ] ArgoCD accessible at https://argocd.talentos.darey.io
- [ ] Health checks passing
- [ ] Monitoring/alerts configured

---

*Last Updated: October 2024*
*Environment: Production*
*Region: eu-west-2*

