# Certificate Management Strategy

This document explains our dual certificate management approach and when to use each method.

## 🎯 Overview

We maintain **two certificate management systems** for different use cases:

1. **ACM + ALB** - For external, public-facing services (PRIMARY)
2. **cert-manager + Let's Encrypt** - Reserved for future internal/NGINX use cases

---

## 📋 Current Setup

### **Primary: ACM + ALB (Active)**

**Used For:**
- ✅ Grafana (`grafana.talentos.darey.io`)
- ✅ ArgoCD (`argocd.talentos.darey.io`)
- ✅ All future external services

**Why:**
- TLS termination at ALB (outside cluster)
- Free AWS-managed certificates
- Automatic renewal (13 months validity)
- Private keys never exposed
- Better security and performance
- AWS-native integration

**Components:**
- ACM wildcard certificate (`*.talentos.darey.io`)
- ALB ingress controller (EKS Auto Mode)
- External DNS for Route53 records

**Status:** ✅ **ACTIVE** - Use this for all external services

---

### **Secondary: cert-manager (Installed but Inactive)**

**Reserved For:**
- Future internal services (if needed)
- NGINX ClusterIP ingresses
- Service mesh certificates
- Custom certificate requirements

**Why Keep It:**
- Flexibility for future requirements
- Internal service TLS
- Non-ALB use cases
- Development/testing scenarios

**Components:**
- cert-manager controller (installed)
- No ClusterIssuer configured yet
- No active certificates

**Status:** 🟡 **STANDBY** - Available if needed

---

## 🔀 Decision Matrix: Which Certificate System to Use?

### **Use ACM + ALB When:**

| Scenario | Reason |
|----------|--------|
| ✅ Public-facing service | ALB is internet-facing |
| ✅ External domain (talentos.darey.io) | Covered by ACM wildcard cert |
| ✅ HTTPS from internet | TLS termination at ALB |
| ✅ Need AWS WAF integration | ALB supports WAF |
| ✅ Need CloudWatch metrics | ALB auto-publishes metrics |
| ✅ Production workload | More reliable, AWS-managed |

**Example Services:**
- Grafana dashboard
- ArgoCD UI
- API gateways
- Web applications
- Any service accessed from internet

---

### **Use cert-manager + Let's Encrypt When:**

| Scenario | Reason |
|----------|--------|
| ✅ Internal service (cluster-only) | NGINX ClusterIP |
| ✅ Service mesh (mTLS) | Internal pod-to-pod encryption |
| ✅ Custom certificate requirements | Need specific cert attributes |
| ✅ Multi-cloud portability | Not AWS-specific |
| ✅ Development environment | Don't want to use AWS resources |

**Example Services (Future):**
- Internal APIs
- Database connections (mTLS)
- Service mesh (Istio/Linkerd)
- Jenkins/internal tools
- Development services

---

## 📊 Side-by-Side Comparison

| Feature | ACM + ALB | cert-manager + Let's Encrypt |
|---------|-----------|------------------------------|
| **Certificate Provider** | AWS ACM | Let's Encrypt |
| **TLS Termination** | At ALB (outside cluster) | At NGINX (inside cluster) |
| **Certificate Storage** | AWS (never exposed) | Kubernetes Secrets |
| **Private Key** | Stays in AWS | In cluster (base64) |
| **Validity Period** | 13 months | 90 days |
| **Renewal** | Automatic (AWS) | Automatic (cert-manager) |
| **Rate Limits** | 2,000/year | 50/week per domain |
| **Cost** | FREE | FREE |
| **Setup Complexity** | Simple (Terraform + annotation) | Medium (ClusterIssuer + Certificate) |
| **AWS Integration** | Native | Via DNS validation |
| **Portability** | AWS only | Any Kubernetes |
| **Best For** | External services | Internal services |

---

## 🚀 How to Use ACM + ALB (Current Active Setup)

### **Step 1: Certificate Already Exists**

The wildcard certificate is managed by Terraform:
```hcl
# terraform/environments/prod/terraform.tfvars
enable_acm_certificate = true
acm_domain_name = "*.talentos.darey.io"
acm_subject_alternative_names = ["talentos.darey.io"]
```

### **Step 2: Create Ingress with ACM**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service-ingress
  namespace: my-namespace
  annotations:
    # ALB Configuration
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    
    # ACM Certificate (get ARN from: terraform output acm_certificate_arn)
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-west-2:586794457112:certificate/[CERT_ID]
    
    # External DNS
    external-dns.alpha.kubernetes.io/hostname: myservice.talentos.darey.io
    external-dns.alpha.kubernetes.io/manage: "true"
spec:
  ingressClassName: alb  # ← Important: Use ALB
  rules:
  - host: myservice.talentos.darey.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

**Key Points:**
- ✅ Use `ingressClassName: alb`
- ✅ Reference ACM certificate via annotation
- ✅ No `tls:` section needed in spec
- ✅ External DNS creates Route53 records automatically

### **Step 3: Commit to GitOps**

```bash
cd gitops
git add argocd/applications/prod/my-service-ingress.yaml
git commit -m "feat: add ALB ingress for my-service"
git push origin main
```

ArgoCD syncs automatically and creates the ALB.

---

## 🔧 How to Use cert-manager (Future Use)

### **Step 1: Create ClusterIssuer (When Needed)**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Let's Encrypt production server
    server: https://acme-v02.api.letsencrypt.org/directory
    email: platform@darey.io
    
    # Private key for ACME account
    privateKeySecretRef:
      name: letsencrypt-prod
    
    # DNS-01 challenge via Route53
    solvers:
    - dns01:
        route53:
          region: eu-west-2
          # Use IAM role from IRSA (if needed)
          # hostedZoneID: Z123456789ABC
```

### **Step 2: Create Ingress with cert-manager**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-service-ingress
  namespace: my-namespace
  annotations:
    # cert-manager annotation
    cert-manager.io/cluster-issuer: letsencrypt-prod
    
    # NGINX-specific (if using NGINX)
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx  # ← Use NGINX
  tls:  # ← This triggers cert-manager
  - hosts:
    - internal.talentos.darey.io
    secretName: internal-service-tls  # cert-manager creates this
  rules:
  - host: internal.talentos.darey.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: internal-service
            port:
              number: 80
```

**Key Points:**
- ✅ Use `ingressClassName: nginx`
- ✅ Add `cert-manager.io/cluster-issuer` annotation
- ✅ Include `tls:` section in spec
- ✅ cert-manager creates the certificate automatically

---

## 📝 Current Active Services

### **Using ACM + ALB:**

| Service | URL | Ingress File | Status |
|---------|-----|--------------|--------|
| Grafana | `grafana.talentos.darey.io` | `grafana-ingress.yaml` | ✅ Configured |
| ArgoCD | `argocd.talentos.darey.io` | `argocd-ingress.yaml` | ✅ Configured |

### **Using cert-manager:**

| Service | URL | Status |
|---------|-----|--------|
| None yet | - | 🟡 Available for future use |

---

## 🔐 Security Comparison

### **ACM + ALB Security:**
- ✅ Private key never leaves AWS
- ✅ TLS 1.2 and TLS 1.3 support
- ✅ Automatic security patches (AWS-managed)
- ✅ CloudTrail audit logs
- ✅ AWS KMS integration (optional)
- ✅ ALB Security Groups
- ✅ AWS WAF integration

### **cert-manager Security:**
- ⚠️ Private key stored in Kubernetes Secret (base64)
- ✅ RBAC for secret access
- ✅ Encryption at rest (if enabled)
- ✅ Automatic renewal (60 days)
- ⚠️ Requires proper secret management
- ✅ Works with any ingress controller

---

## 🎯 Best Practices

### **For External Services (Internet-Facing):**

1. **Always use ACM + ALB**
   - Better security (private key never exposed)
   - AWS-managed and more reliable
   - Better performance (TLS offload)
   - CloudWatch metrics included

2. **Use the wildcard certificate**
   - One cert for all subdomains
   - No need to create individual certs
   - Simpler management

3. **Enable External DNS**
   - Automatic DNS record creation
   - No manual Route53 updates needed

### **For Internal Services (Future):**

1. **Use cert-manager if needed**
   - Internal services without ALB
   - Service mesh mTLS
   - Custom certificate requirements

2. **Create specific ClusterIssuer**
   - Separate from production
   - Consider staging Let's Encrypt first

3. **Use DNS-01 challenge**
   - Works behind firewalls
   - No need to expose HTTP endpoint

---

## 🚨 Important Notes

### **Don't Mix Approaches:**

❌ **Wrong:** Using cert-manager annotation with ALB ingress
```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod  # ← Don't use with ALB
spec:
  ingressClassName: alb  # ← ALB uses ACM
```

❌ **Wrong:** Using ACM certificate ARN with NGINX
```yaml
annotations:
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...  # ← Only works with ALB
spec:
  ingressClassName: nginx  # ← NGINX doesn't understand ACM
```

✅ **Correct:** Match certificate system with ingress controller
```yaml
# For ALB
annotations:
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
spec:
  ingressClassName: alb

# For NGINX
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls: [...]
```

---

## 📚 Additional Resources

### **ACM + ALB:**
- [Complete Ingress Setup Guide](./INGRESS_SETUP.md)
- [EKS Auto Mode ALB](../../../terraform/modules/eks-cluster/EKS_AUTO_MODE_ALB.md)
- [AWS Load Balancer Controller Docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

### **cert-manager:**
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [DNS-01 Challenge with Route53](https://cert-manager.io/docs/configuration/acme/dns01/route53/)

---

## ✅ Summary

**Current Strategy:**
- ✅ **ACM + ALB** for all external services (PRIMARY)
- 🟡 **cert-manager** installed but inactive (STANDBY)
- ✅ Flexibility to use either approach as needed
- ✅ No conflicts between the two systems

**When to Use What:**
- **External service?** → Use ACM + ALB
- **Internal service?** → Consider cert-manager (if needed)
- **In doubt?** → Use ACM + ALB (simpler and more secure)

**Next Steps:**
1. Apply Terraform to create ACM certificate
2. Update ingress manifests with certificate ARN
3. Deploy via GitOps
4. Access services via HTTPS

---

*Last Updated: October 2024*
*Environment: Production*
*Strategy: ACM + ALB (Primary), cert-manager (Standby)*

