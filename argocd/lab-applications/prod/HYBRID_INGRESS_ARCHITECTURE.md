# 🌐 **Complete Hybrid Ingress Architecture**

## 🏗️ **Architecture Overview**

### **Hybrid Ingress Strategy**
- **ALB + ACM**: Main Lab Controller API (`labcontroller-api.talentos.darey.io`)
- **NGINX + cert-manager**: Dynamic Lab Instances (`*.projectlabs-api.talentos.darey.io`)

---

## 📊 **Ingress Components**

### **1. ALB Ingress (Main API)**
**File**: `lab-controller-ingress.yaml`
- **Domain**: `labcontroller-api.talentos.darey.io`
- **Certificate**: ACM wildcard (`*.talentos.darey.io`)
- **Purpose**: Lab management API endpoints
- **Features**: HTTP/2, enhanced POST support, health checks

### **2. NGINX Ingress (Lab Instances)**
**File**: `lab-instances-nginx-ingress.yaml`
- **Domain**: `*.projectlabs-api.talentos.darey.io`
- **Certificate**: cert-manager + Route53 DNS-01
- **Purpose**: Individual lab environments
- **Features**: WebSocket support, dynamic subdomains, long timeouts

---

## 🎯 **Why Hybrid Architecture?**

### **✅ ALB for Main API**
- **Simple Endpoints**: Health checks, lab management
- **ACM Certificate**: Already working and validated
- **Better Performance**: AWS-native load balancing
- **Cost Effective**: No additional NGINX overhead

### **✅ NGINX for Lab Instances**
- **Dynamic Subdomains**: `session-id.projectlabs-api.talentos.darey.io`
- **WebSocket Support**: Required for VS Code, Jupyter
- **Long Timeouts**: Labs run for hours
- **Flexible Routing**: Better for complex lab environments

---

## 🔧 **NGINX Configuration Details**

### **WebSocket Support**
```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-set-header: "Upgrade $http_upgrade, Connection $connection_upgrade"
```

### **Extended Timeouts**
```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"    # 1 hour
  nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"   # 1 hour
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"  # 1 minute
```

### **Large File Support**
```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-body-size: "0"  # No limit
```

### **Security Headers**
```yaml
annotations:
  nginx.ingress.kubernetes.io/configuration-snippet: |
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
```

---

## 🔄 **Certificate Management**

### **ACM Certificate (ALB)**
- **Domain**: `*.talentos.darey.io`
- **Management**: AWS Certificate Manager
- **Validation**: DNS validation via Route53
- **Renewal**: Automatic by AWS
- **Cost**: FREE

### **cert-manager Certificate (NGINX)**
- **Domain**: `*.projectlabs-api.talentos.darey.io`
- **Management**: cert-manager operator
- **Validation**: Route53 DNS-01 challenge
- **Renewal**: Automatic by cert-manager
- **Cost**: FREE (Let's Encrypt)

---

## 🚀 **Lab Creation Flow**

### **1. Main API (ALB)**
```
User Request → labcontroller-api.talentos.darey.io → ALB → Lab Controller API
```

### **2. Lab Instance (NGINX)**
```
Lab Access → session-id.projectlabs-api.talentos.darey.io → NGINX → Lab Pod
```

### **3. Dynamic Resource Creation**
1. **API Request**: POST to `/labs/start`
2. **Lab Controller**: Creates Kubernetes resources
3. **NGINX Ingress**: Routes traffic to lab instance
4. **cert-manager**: Creates TLS certificate
5. **External DNS**: Creates Route53 record

---

## 📋 **File Structure**

```
gitops/argocd/lab-applications/prod/
├── lab-controller-deployment.yaml        # Complete lab-controller stack
├── lab-controller-ingress.yaml          # ALB ingress for main API
├── lab-instances-nginx-ingress.yaml     # NGINX ingress for lab instances
├── lab-controller-redis.yaml            # Redis for session management
└── README.md                             # Documentation
```

---

## 🔍 **Ingress Classes**

### **ALB Ingress Class**
```yaml
spec:
  ingressClassName: alb
```

### **NGINX Ingress Class**
```yaml
spec:
  ingressClassName: nginx
```

---

## 🧪 **Lab Types Supported**

### **Ubuntu Labs**
- **Image**: `dareyprojectabs/ubuntu:22.04.02`
- **Access**: `session-id.projectlabs-api.talentos.darey.io`
- **Features**: Terminal access, file management

### **VS Code Labs**
- **Image**: `dareyprojectabs/vscode-server:1.0.1`
- **Access**: `session-id.projectlabs-api.talentos.darey.io`
- **Features**: WebSocket support, real-time editing

### **Jupyter Labs**
- **Image**: `dareyprojectabs/jupyter-notebook:v3`
- **Access**: `session-id.projectlabs-api.talentos.darey.io`
- **Features**: WebSocket support, interactive notebooks

---

## 🎯 **Benefits of Hybrid Architecture**

### **✅ Best of Both Worlds**
- **ALB**: AWS-native performance for API
- **NGINX**: Flexible routing for labs
- **ACM**: Reliable certificates for API
- **cert-manager**: Dynamic certificates for labs

### **✅ Optimized for Use Cases**
- **API**: Simple, fast, reliable
- **Labs**: Complex, flexible, WebSocket support
- **Certificates**: Appropriate tool for each use case
- **Cost**: Optimized resource usage

---

## 🚀 **Deployment Process**

### **1. Commit All Files**
```bash
cd gitops
git add argocd/lab-applications/prod/
git commit -m "feat: complete hybrid ingress architecture

- ALB ingress for main API (labcontroller-api.talentos.darey.io)
- NGINX ingress for lab instances (*.projectlabs-api.talentos.darey.io)
- Enhanced ALB configuration for POST requests
- NGINX WebSocket support for lab environments
- Complete certificate management strategy"
git push origin main
```

### **2. ArgoCD Sync**
- **ALB**: Creates load balancer for main API
- **NGINX**: Configures ingress controller for labs
- **cert-manager**: Creates wildcard certificate
- **External DNS**: Creates Route53 records

### **3. Verification**
```bash
# Check ALB ingress
kubectl get ingress -n lab-controller lab-controller-ingress

# Check NGINX ingress
kubectl get ingress -n lab-controller lab-instances-ingress-template

# Test main API
curl https://labcontroller-api.talentos.darey.io/health

# Test lab creation (will create NGINX ingress dynamically)
curl -X POST "https://labcontroller-api.talentos.darey.io/labs/start" \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test-user", "template": "ubuntu", "ttl": 3600}'
```

---

## 🎉 **Expected Results**

### **✅ Complete Architecture**
- **Main API**: ALB + ACM working
- **Lab Instances**: NGINX + cert-manager ready
- **Certificates**: Both ACM and cert-manager active
- **DNS**: Route53 records created automatically

### **✅ Lab Functionality**
- **Creation**: POST requests working
- **Access**: Dynamic subdomains accessible
- **WebSocket**: Real-time features working
- **TLS**: All connections secured

---

**🎯 This hybrid architecture provides the best of both worlds: AWS-native performance for the API and flexible NGINX routing for dynamic lab instances.**
