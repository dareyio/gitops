# 🔄 **GitOps Update: Lab Controller Ingress & Redis**

## ✅ **Files Created/Updated**

### **1. Lab Controller Ingress**
**File**: `gitops/argocd/applications/prod/lab-controller-ingress.yaml`

**Key Features**:
- ✅ **ALB + ACM**: Uses existing ACM certificate
- ✅ **External DNS**: Automatic Route53 record creation
- ✅ **Health Checks**: Configured for `/health/live` endpoint
- ✅ **POST Request Support**: Added ALB annotations for better handling
- ✅ **Security**: Proper security groups and tags

**ALB Improvements Added**:
```yaml
# ALB annotations for better POST request handling
alb.ingress.kubernetes.io/target-group-attributes: 'stickiness.enabled=false,routing.http2.enabled=true'
alb.ingress.kubernetes.io/load-balancer-attributes: 'routing.http2.enabled=true,idle_timeout.timeout_seconds=60'
```

### **2. Redis Deployment**
**File**: `gitops/argocd/applications/prod/lab-controller-redis.yaml`

**Key Features**:
- ✅ **Redis 7 Alpine**: Lightweight and efficient
- ✅ **Persistence**: AOF enabled with periodic saves
- ✅ **Resource Limits**: CPU and memory constraints
- ✅ **Namespace**: `lab-controller` namespace
- ✅ **Service**: ClusterIP service for internal communication

## 🎯 **Architecture Maintained**

### **✅ Hybrid Architecture (As Agreed)**
- **Main API**: ALB + ACM (`labcontroller-api.talentos.darey.io`)
- **Lab Instances**: NGINX + cert-manager (`*.projectlabs-api.talentos.darey.io`)

### **✅ ALB Configuration**
- **Certificate**: ACM wildcard (`*.talentos.darey.io`)
- **Health Checks**: `/health/live` endpoint
- **External DNS**: Automatic Route53 management
- **POST Support**: Enhanced ALB configuration

## 🚀 **Deployment Process**

### **Step 1: Commit Changes**
```bash
cd gitops
git add argocd/applications/prod/lab-controller-ingress.yaml
git add argocd/applications/prod/lab-controller-redis.yaml
git commit -m "feat: add lab-controller ingress and redis deployment

- ALB ingress with ACM certificate for main API
- Redis deployment for session management
- External DNS integration for automatic Route53 records
- Enhanced ALB configuration for POST request handling"
git push origin main
```

### **Step 2: ArgoCD Sync**
- ArgoCD will detect the new files
- Automatically sync the ingress and redis deployment
- ALB will be created with improved configuration
- External DNS will create Route53 record

### **Step 3: Verification**
```bash
# Check ingress status
kubectl get ingress -n lab-controller

# Check redis deployment
kubectl get pods -n lab-controller -l app=redis

# Check ALB creation
kubectl describe ingress lab-controller-ingress -n lab-controller

# Test API health
curl https://labcontroller-api.talentos.darey.io/health
```

## 🔍 **Expected Results**

### **✅ ALB Creation**
- **Load Balancer**: New ALB with improved configuration
- **Target Group**: Health checks on `/health/live`
- **Certificate**: ACM certificate attached
- **DNS**: Route53 A record created automatically

### **✅ Redis Deployment**
- **Pod**: Redis 7 Alpine running
- **Service**: ClusterIP service for internal communication
- **Persistence**: AOF enabled for data durability
- **Resources**: Proper CPU/memory limits

### **✅ Lab Creation Fix**
- **POST Requests**: Should work with improved ALB configuration
- **Session Management**: Redis available for lab sessions
- **Health Checks**: All components healthy

## ⏱️ **Timeline**

1. **GitOps Sync**: 1-2 minutes
2. **ALB Creation**: 2-3 minutes
3. **DNS Propagation**: 1-2 minutes
4. **Total Time**: 5-7 minutes

## 🧪 **Testing After Deployment**

### **1. Check Components**
```bash
# Ingress
kubectl get ingress -n lab-controller

# Redis
kubectl get pods -n lab-controller -l app=redis

# Lab Controller
kubectl get pods -n lab-controller -l app=lab-controller
```

### **2. Test API**
```bash
# Health check
curl https://labcontroller-api.talentos.darey.io/health

# Should show: {"status":"ok","checks":{"redis":"ok",...}}
```

### **3. Test Lab Creation**
```bash
# Generate token
python3 practice-labs/simple_token_generator.py

# Create lab
curl -X POST "https://labcontroller-api.talentos.darey.io/labs/start" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test-user-123", "template": "ubuntu", "ttl": 3600}'
```

## 🎉 **Expected Success**

- ✅ **ALB Working**: Improved configuration handles POST requests
- ✅ **Redis Available**: Session management working
- ✅ **DNS Resolved**: `labcontroller-api.talentos.darey.io` accessible
- ✅ **Lab Creation**: POST requests succeed
- ✅ **Architecture**: Hybrid approach maintained

---

**🎯 Ready to commit and deploy! The improved ALB configuration should resolve the POST request issue while maintaining the hybrid architecture.**
