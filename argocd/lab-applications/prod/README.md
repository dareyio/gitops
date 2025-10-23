# 🧪 **Lab Applications - GitOps Configuration**

This directory contains ArgoCD application manifests for the **Lab Controller** and all dynamically created lab instances.

---

## 📋 **Architecture Overview**

### **Lab Controller Application**
- **Name**: `lab-controller-app`
- **Namespace**: `lab-controller`
- **Purpose**: Manages lab creation, lifecycle, and monitoring
- **Components**: API, Redis, Ingress, RBAC

### **Dynamic Lab Instances**
- **Namespace**: `default` (or user-specific namespaces)
- **Purpose**: Individual lab environments (Ubuntu, VS Code, Jupyter)
- **Management**: Created and managed by Lab Controller API
- **Monitoring**: Tracked by ArgoCD through the Lab Controller

---

## 🏗️ **File Structure**

```
argocd/lab-applications/prod/
├── lab-controller-app.yaml           # ArgoCD Application definition
├── lab-controller-deployment.yaml    # Lab Controller components
├── lab-controller-ingress.yaml       # ALB ingress for main API
├── lab-controller-redis.yaml         # Redis for session management
└── README.md                         # This file
```

---

## 🚀 **Components Managed**

### **1. Lab Controller API**
- **Image**: `dareyioinfra/lab-controller:latest`
- **Replicas**: 3 (high availability)
- **Resources**: CPU/Memory limits
- **Health Checks**: `/health/live` and `/health/ready`

### **2. Redis Session Store**
- **Image**: `redis:7-alpine`
- **Purpose**: Lab session management
- **Persistence**: AOF enabled
- **Resources**: Optimized for session storage

### **3. ALB Ingress**
- **Domain**: `labcontroller-api.talentos.darey.io`
- **Certificate**: ACM wildcard (`*.talentos.darey.io`)
- **Features**: HTTP/2, enhanced POST support, health checks

### **4. RBAC & Security**
- **Service Account**: `lab-controller-sa`
- **IRSA**: ECR access via IAM role
- **Permissions**: Full lab lifecycle management

---

## 🎯 **Lab Instance Management**

### **How It Works**
1. **User Request**: POST to `/labs/start` endpoint
2. **Lab Controller**: Creates Kubernetes resources
3. **ArgoCD Monitoring**: Tracks all created resources
4. **Lifecycle Management**: Automatic cleanup and monitoring

### **Dynamic Resources Created**
- **Pods**: Lab environment containers
- **Services**: Internal communication
- **Ingresses**: NGINX + cert-manager for lab access
- **Secrets**: TLS certificates for lab domains

### **Lab Types Supported**
- **Ubuntu**: `dareyprojectabs/ubuntu:22.04.02`
- **VS Code**: `dareyprojectabs/vscode-server:1.0.1`
- **Jupyter**: `dareyprojectabs/jupyter-notebook:v3`

---

## 🔄 **ArgoCD Application Configuration**

### **Sync Policy**
```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources not in Git
    selfHeal: true   # Fix drift automatically
  syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
```

### **Benefits**
- ✅ **GitOps**: All lab resources tracked in Git
- ✅ **Monitoring**: ArgoCD UI shows all lab instances
- ✅ **Self-Healing**: Automatic drift correction
- ✅ **Audit Trail**: Complete history of lab lifecycle
- ✅ **Resource Management**: Automatic cleanup

---

## 🧪 **Lab Creation Flow**

### **1. API Request**
```bash
curl -X POST "https://labcontroller-api.talentos.darey.io/labs/start" \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "user-123", "template": "ubuntu", "ttl": 3600}'
```

### **2. Resource Creation**
- **Namespace**: Created if needed
- **Pod**: Lab environment container
- **Service**: Internal communication
- **Ingress**: NGINX + cert-manager
- **Secret**: ECR image pull secret

### **3. ArgoCD Tracking**
- **Application**: `lab-controller-app` manages all resources
- **Monitoring**: ArgoCD UI shows lab status
- **Health Checks**: Continuous monitoring

### **4. Lab Access**
- **URL**: `https://session-id.projectlabs-api.talentos.darey.io`
- **TLS**: Automatic cert-manager certificate
- **WebSocket**: NGINX supports real-time features

---

## 📊 **Monitoring & Observability**

### **ArgoCD UI**
- **Application Status**: Overall health
- **Resource Tree**: All lab instances
- **Sync Status**: Git vs cluster state
- **History**: Complete audit trail

### **Grafana Dashboards**
- **Lab Metrics**: Resource usage per lab
- **API Metrics**: Request rates and errors
- **Redis Metrics**: Session store performance
- **ALB Metrics**: Load balancer statistics

### **Prometheus Alerts**
- **Lab Failures**: Pod crash loops
- **API Errors**: High error rates
- **Resource Limits**: CPU/Memory usage
- **Certificate Expiry**: TLS certificate warnings

---

## 🔧 **Configuration Management**

### **Environment Variables**
```yaml
env:
  - name: REDIS_HOST
    value: "redis.lab-controller.svc.cluster.local"
  - name: LAB_BASE_URL
    value: "https://projectlabs-api.talentos.darey.io"
  - name: WILDCARD_TLS_SECRET_NAME
    value: "wildcard-projectlabs-api-talentos-darey-io"
```

### **Resource Limits**
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

### **Health Checks**
```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 10
```

---

## 🚀 **Deployment Process**

### **1. Update GitOps Repository**
```bash
cd gitops
git add argocd/lab-applications/prod/
git commit -m "feat: add lab-controller application with dynamic lab management"
git push origin main
```

### **2. ArgoCD Sync**
- **Automatic**: ArgoCD detects changes
- **Manual**: Force sync via UI if needed
- **Status**: Monitor in ArgoCD dashboard

### **3. Verification**
```bash
# Check application status
kubectl get application lab-controller-app -n argocd

# Check lab-controller pods
kubectl get pods -n lab-controller

# Test API health
curl https://labcontroller-api.talentos.darey.io/health
```

---

## 🔐 **Security Features**

### **IRSA Authentication**
- **Service Account**: `lab-controller-sa`
- **IAM Role**: `prod-lab-controller-ecr-role`
- **Permissions**: ECR access, Kubernetes API access

### **RBAC Permissions**
- **Namespaces**: Create and manage lab namespaces
- **Pods**: Full lifecycle management
- **Services**: Create and update services
- **Ingresses**: Manage lab access points
- **Secrets**: Handle TLS certificates

### **Network Security**
- **ALB**: TLS termination at load balancer
- **NGINX**: Additional security headers
- **Pod Security**: Security contexts enforced

---

## 📈 **Scaling & Performance**

### **Horizontal Scaling**
- **Lab Controller**: 3 replicas for high availability
- **Redis**: Single instance (can be clustered if needed)
- **ALB**: Auto-scaling based on traffic

### **Resource Optimization**
- **CPU**: Burstable with limits
- **Memory**: Optimized for session storage
- **Storage**: EmptyDir for Redis (can be persistent if needed)

### **Performance Tuning**
- **ALB**: HTTP/2 enabled, increased timeouts
- **Redis**: AOF persistence, optimized saves
- **API**: Health checks and readiness probes

---

## 🔍 **Troubleshooting**

### **Common Issues**

#### **Lab Creation Fails**
```bash
# Check lab-controller logs
kubectl logs -n lab-controller deployment/lab-controller

# Check Redis connectivity
kubectl exec -n lab-controller deployment/redis -- redis-cli ping

# Check ArgoCD application status
kubectl get application lab-controller-app -n argocd
```

#### **ALB Not Working**
```bash
# Check ingress status
kubectl get ingress -n lab-controller

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check certificate status
aws acm describe-certificate --certificate-arn [ARN] --region eu-west-2
```

#### **Redis Connection Issues**
```bash
# Check Redis pod status
kubectl get pods -n lab-controller -l app=redis

# Test Redis connectivity
kubectl exec -n lab-controller deployment/redis -- redis-cli info

# Check service connectivity
kubectl get svc -n lab-controller redis
```

---

## 🎯 **Benefits of This Architecture**

### **✅ GitOps Benefits**
- **Version Control**: All lab configurations in Git
- **Audit Trail**: Complete history of changes
- **Rollback**: Easy revert to previous states
- **Collaboration**: Team can review and approve changes

### **✅ ArgoCD Benefits**
- **Monitoring**: Visual representation of all resources
- **Self-Healing**: Automatic drift correction
- **Sync Status**: Clear Git vs cluster state
- **Resource Management**: Automatic cleanup

### **✅ Operational Benefits**
- **Centralized Management**: Single application for all labs
- **Consistent Configuration**: Standardized lab environments
- **Easy Scaling**: Add new lab types via Git
- **Monitoring**: Complete observability

---

## 📚 **Next Steps**

### **Immediate Actions**
1. **Update GitOps Repository URL** in `lab-controller-app.yaml`
2. **Commit and Push** changes to GitOps repository
3. **Monitor ArgoCD** for application sync
4. **Test Lab Creation** via API

### **Future Enhancements**
- **Lab Templates**: Add more lab types
- **Resource Quotas**: Implement namespace limits
- **Monitoring**: Enhanced Grafana dashboards
- **Backup**: Redis persistence strategy

---

**🎯 This architecture provides complete GitOps management of the lab ecosystem with full ArgoCD monitoring and control.**
