# Quick Reference: Adding New Services

## 🚀 Quick Guide: Expose a New Service via HTTPS

### **Prerequisites:**
- ACM certificate exists (wildcard `*.talentos.darey.io`)
- External DNS is running
- Service exists in Kubernetes

---

## 📝 Steps to Expose a Service

### **1. Get Certificate ARN**
```bash
cd terraform
terraform output acm_certificate_arn
```

Copy the ARN: `arn:aws:acm:eu-west-2:586794457112:certificate/[CERT_ID]`

---

### **2. Create Ingress YAML**

Create: `gitops/argocd/applications/prod/[SERVICE-NAME]-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: [SERVICE-NAME]-ingress
  namespace: [NAMESPACE]
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: [PASTE_CERT_ARN_HERE]
    external-dns.alpha.kubernetes.io/hostname: [subdomain].talentos.darey.io
    external-dns.alpha.kubernetes.io/manage: "true"
spec:
  ingressClassName: alb
  rules:
  - host: [subdomain].talentos.darey.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: [SERVICE-NAME]
            port:
              number: [PORT]
```

**Replace:**
- `[SERVICE-NAME]` - Your service name
- `[NAMESPACE]` - Kubernetes namespace
- `[PASTE_CERT_ARN_HERE]` - ACM certificate ARN
- `[subdomain]` - Subdomain (e.g., `myapp`)
- `[PORT]` - Service port number

---

### **3. Commit and Push**

```bash
cd gitops
git add argocd/applications/prod/[SERVICE-NAME]-ingress.yaml
git commit -m "feat: add ALB ingress for [SERVICE-NAME]"
git push origin main
```

---

### **4. Wait for Sync**

ArgoCD will automatically:
- ✅ Create the ingress
- ✅ Provision ALB (2-3 minutes)
- ✅ Create DNS record (1-2 minutes)
- ✅ Enable HTTPS with ACM cert

---

### **5. Verify**

```bash
# Check ingress
kubectl get ingress -n [NAMESPACE]

# Check DNS
dig [subdomain].talentos.darey.io

# Access service
curl https://[subdomain].talentos.darey.io
```

---

## 🎯 Common Scenarios

### **HTTP Backend (Most Common)**
```yaml
alb.ingress.kubernetes.io/backend-protocol: HTTP  # Default
```

### **HTTPS Backend (e.g., ArgoCD)**
```yaml
alb.ingress.kubernetes.io/backend-protocol: HTTPS
```

### **Custom Health Check**
```yaml
alb.ingress.kubernetes.io/healthcheck-path: /health
alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
```

### **Multiple Paths**
```yaml
spec:
  rules:
  - host: myapp.talentos.darey.io
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

---

## 📋 Useful Commands

### **Get ACM Certificate ARN**
```bash
terraform output acm_certificate_arn
```

### **List All Ingresses**
```bash
kubectl get ingress --all-namespaces
```

### **Check ALB Status**
```bash
kubectl describe ingress [INGRESS-NAME] -n [NAMESPACE]
```

### **Get ALB DNS Name**
```bash
kubectl get ingress [INGRESS-NAME] -n [NAMESPACE] -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### **Check External DNS Logs**
```bash
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns --tail=50
```

### **Verify DNS Record**
```bash
dig [subdomain].talentos.darey.io
# Or
nslookup [subdomain].talentos.darey.io
```

### **Test HTTPS**
```bash
curl -I https://[subdomain].talentos.darey.io
```

---

## 🔍 Troubleshooting

### **Ingress Created but No ALB**
```bash
# Check events
kubectl describe ingress [INGRESS-NAME] -n [NAMESPACE]

# Look for errors in events
# Common issues: Invalid certificate ARN, missing ingressClassName
```

### **ALB Created but DNS Not Working**
```bash
# Check External DNS
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns --tail=20

# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id [ZONE_ID]
```

### **HTTPS Not Working**
```bash
# Verify certificate ARN is correct
kubectl get ingress [INGRESS-NAME] -n [NAMESPACE] -o yaml | grep certificate-arn

# Check ALB listeners
aws elbv2 describe-listeners --load-balancer-arn [ALB_ARN]
```

### **Service Unreachable (504 Gateway Timeout)**
```bash
# Check pods are running
kubectl get pods -n [NAMESPACE]

# Check service endpoints
kubectl get endpoints [SERVICE-NAME] -n [NAMESPACE]

# Check ALB target group health
aws elbv2 describe-target-health --target-group-arn [TG_ARN]
```

---

## 📚 Templates

### **Basic Web Application**
See: `grafana-ingress.yaml`

### **API with HTTPS Backend**
See: `argocd-ingress.yaml`

### **New Service Template**
```bash
# Copy existing template
cp grafana-ingress.yaml myapp-ingress.yaml

# Edit with your values
# - Change name, namespace, host, service, port
```

---

## ✅ Checklist

Before creating ingress:
- [ ] Service exists and is running
- [ ] Service has endpoints (pods running)
- [ ] ACM certificate ARN obtained
- [ ] Subdomain chosen (under `talentos.darey.io`)
- [ ] Health check path known
- [ ] Backend protocol identified (HTTP or HTTPS)

After creating ingress:
- [ ] Ingress created in cluster
- [ ] ALB provisioned (check AWS Console)
- [ ] DNS record created (check Route53)
- [ ] DNS resolves to ALB
- [ ] HTTPS works with valid certificate
- [ ] HTTP redirects to HTTPS
- [ ] Service accessible
- [ ] Health checks passing

---

*See also:*
- [INGRESS_SETUP.md](./INGRESS_SETUP.md) - Complete setup guide
- [CERTIFICATE_STRATEGY.md](./CERTIFICATE_STRATEGY.md) - Certificate management strategy

