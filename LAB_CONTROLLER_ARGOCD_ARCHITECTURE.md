# 🎯 **Lab Controller ArgoCD Application Architecture**

## ✅ **New Structure Created**

### **📁 Directory Structure**
```
gitops/argocd/
├── applications/prod/
│   └── lab-controller-app.yaml          # ArgoCD Application definition
└── lab-applications/prod/
    ├── lab-controller-deployment.yaml    # Complete lab-controller stack
    ├── lab-controller-ingress.yaml       # ALB ingress for main API
    ├── lab-controller-redis.yaml         # Redis for session management
    └── README.md                         # Comprehensive documentation
```

## 🏗️ **Architecture Benefits**

### **✅ Separate ArgoCD Application**
- **Application Name**: `lab-controller-app`
- **Namespace**: `lab-controller`
- **Purpose**: Dedicated management of lab ecosystem
- **Monitoring**: All lab instances tracked in ArgoCD UI

### **✅ Complete Lab Management**
- **Lab Controller API**: 3 replicas with health checks
- **Redis Session Store**: Persistent session management
- **ALB Ingress**: Enhanced configuration for POST requests
- **RBAC**: Full permissions for lab lifecycle management

### **✅ Dynamic Lab Tracking**
- **All Lab Instances**: Monitored by ArgoCD
- **Resource Management**: Automatic cleanup and monitoring
- **GitOps**: All lab configurations version controlled
- **Audit Trail**: Complete history of lab lifecycle

## 🔄 **How It Works**

### **1. ArgoCD Application**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: lab-controller-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/your-org/gitops-repo.git
    path: argocd/lab-applications/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: lab-controller
  syncPolicy:
    automated:
      prune: true      # Remove resources not in Git
      selfHeal: true   # Fix drift automatically
```

### **2. Lab Creation Flow**
1. **User Request** → Lab Controller API
2. **API Creates** → Kubernetes resources (pods, services, ingresses)
3. **ArgoCD Tracks** → All created resources
4. **Monitoring** → Complete visibility in ArgoCD UI

### **3. Resource Management**
- **GitOps**: All configurations in Git
- **Self-Healing**: ArgoCD corrects drift
- **Cleanup**: Automatic resource removal
- **Audit**: Complete change history

## 🎯 **Key Features**

### **✅ Complete Lab Stack**
- **API**: Lab Controller with 3 replicas
- **Redis**: Session management with persistence
- **Ingress**: ALB with enhanced POST support
- **RBAC**: Full lab management permissions

### **✅ ArgoCD Integration**
- **Application**: Dedicated `lab-controller-app`
- **Monitoring**: All lab instances visible
- **Sync Policy**: Automated pruning and self-healing
- **Namespace**: Automatic creation

### **✅ Enhanced ALB Configuration**
```yaml
annotations:
  alb.ingress.kubernetes.io/target-group-attributes: 'stickiness.enabled=false,routing.http2.enabled=true'
  alb.ingress.kubernetes.io/load-balancer-attributes: 'routing.http2.enabled=true,idle_timeout.timeout_seconds=60'
```

## 🚀 **Deployment Process**

### **Step 1: Update GitOps Repository URL**
Edit `gitops/argocd/applications/prod/lab-controller-app.yaml`:
```yaml
source:
  repoURL: https://github.com/YOUR-ORG/YOUR-GITOPS-REPO.git  # Update this
  targetRevision: main
```

### **Step 2: Commit Changes**
```bash
cd gitops
git add argocd/applications/prod/lab-controller-app.yaml
git add argocd/lab-applications/prod/
git commit -m "feat: add lab-controller ArgoCD application

- Separate ArgoCD application for lab ecosystem
- Complete lab-controller stack with Redis
- Enhanced ALB configuration for POST requests
- Full RBAC permissions for lab management
- Dynamic lab instance tracking via ArgoCD"
git push origin main
```

### **Step 3: ArgoCD Sync**
- **Automatic**: ArgoCD detects new application
- **Manual**: Force sync via ArgoCD UI if needed
- **Monitoring**: Watch sync status in ArgoCD dashboard

## 🔍 **Verification Steps**

### **1. Check ArgoCD Application**
```bash
kubectl get application lab-controller-app -n argocd
kubectl describe application lab-controller-app -n argocd
```

### **2. Check Lab Controller Resources**
```bash
kubectl get all -n lab-controller
kubectl get ingress -n lab-controller
```

### **3. Test API Health**
```bash
curl https://labcontroller-api.talentos.darey.io/health
# Should show: {"status":"ok","checks":{"redis":"ok",...}}
```

### **4. Test Lab Creation**
```bash
# Generate token
python3 practice-labs/simple_token_generator.py

# Create lab
curl -X POST "https://labcontroller-api.talentos.darey.io/labs/start" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test-user-123", "template": "ubuntu", "ttl": 3600}'
```

## 🎉 **Expected Results**

### **✅ ArgoCD Application**
- **Status**: Synced and healthy
- **Resources**: All lab-controller components deployed
- **Monitoring**: Complete visibility in ArgoCD UI

### **✅ Lab Controller Stack**
- **API**: 3 replicas running with health checks
- **Redis**: Session store operational
- **ALB**: Enhanced configuration active
- **RBAC**: Full permissions configured

### **✅ Lab Management**
- **Creation**: POST requests working
- **Monitoring**: All lab instances tracked
- **Cleanup**: Automatic resource management
- **Audit**: Complete change history

## 🔧 **Configuration Details**

### **ArgoCD Application Settings**
- **Sync Policy**: Automated with pruning
- **Self-Healing**: Automatic drift correction
- **Namespace**: Auto-creation enabled
- **History**: 10 revision limit

### **Lab Controller Configuration**
- **Replicas**: 3 for high availability
- **Resources**: CPU/Memory limits set
- **Health Checks**: Liveness and readiness probes
- **IRSA**: ECR access via IAM role

### **Redis Configuration**
- **Persistence**: AOF enabled
- **Saves**: Optimized intervals
- **Resources**: Memory-optimized
- **Storage**: EmptyDir (can be persistent)

## 🎯 **Benefits Achieved**

### **✅ Separation of Concerns**
- **Infrastructure**: Managed by main ArgoCD applications
- **Lab Ecosystem**: Dedicated `lab-controller-app`
- **Clear Boundaries**: Easy to manage and monitor

### **✅ Complete Visibility**
- **ArgoCD UI**: All lab instances visible
- **Resource Tree**: Complete lab ecosystem view
- **Sync Status**: Git vs cluster state
- **History**: Complete audit trail

### **✅ Enhanced Management**
- **GitOps**: All configurations version controlled
- **Self-Healing**: Automatic drift correction
- **Monitoring**: Continuous health checks
- **Scaling**: Easy to add new lab types

---

**🎯 This architecture provides complete GitOps management of the lab ecosystem with dedicated ArgoCD application monitoring and full visibility into all dynamically created lab instances.**
