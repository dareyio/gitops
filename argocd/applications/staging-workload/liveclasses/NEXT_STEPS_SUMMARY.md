# Next Steps Summary - Staging BBB Deployment

## ✅ Completed Actions

1. **Fixed StorageClass**: MongoDB now uses `gp2` instead of `gp3`
2. **Reduced Resource Requests**: FreeSWITCH and Kurento reduced to 1 CPU/2GB per pod
3. **Updated Terraform**: Cluster node instance type changed from `t3.medium` to `t3.xlarge`
4. **Committed Changes**: Terraform changes pushed to repository

## ⏳ Pending Actions

### 1. Terraform Apply (State Lock Detected)

**Status**: Terraform state is locked (Lock ID: `f0e267aa-94a8-400f-974d-027f0c09f303`)

**Action Required**:
```bash
cd /Users/dare/Desktop/xterns/darey-new/terraform
./docker-run.sh staging apply -auto-approve
```

**What This Will Do**:
- Create MongoDB secrets in AWS Secrets Manager:
  - `staging/liveclasses/mongodb`
  - `staging/liveclasses/mongodb-keyfile`
  - `staging/liveclasses/bbb-api-secret`
- Update EKS node group to use `t3.xlarge` instances
- New nodes will join cluster (takes 5-10 minutes)

**After Apply**:
- ExternalSecrets will automatically sync secrets to Kubernetes
- MongoDB pods should start once secrets are available
- New larger nodes will provide capacity for FreeSWITCH/Kurento pods

### 2. BBB Images

**Issue**: BBB doesn't publish official Docker images on Docker Hub

**Options**:

#### Option A: Use BBB Docker Repository (Recommended)
BBB maintains a Docker repository at: https://github.com/bigbluebutton/docker

**Steps**:
1. Clone the repository
2. Build images from source
3. Push to ECR

#### Option B: Use Community Images
Check for community-maintained BBB images or use alternative sources

#### Option C: Build from BBB Source
Build BBB components from the main repository

**Current Status**: ECR repositories created, but images need to be built/pushed

### 3. Monitor Cluster Scaling

After Terraform apply completes:

```bash
# Watch for new nodes
kubectl get nodes -w

# Check node capacity
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory

# Expected: 6 nodes with 4 CPU, ~16GB each = 24 CPU, ~96GB total
```

### 4. Monitor Pod Status

```bash
# Check all pods
kubectl get pods -n liveclasses

# Check MongoDB
kubectl get pods -n liveclasses -l app=mongodb

# Check BBB components
kubectl get pods -n liveclasses | grep -E "bbb|freeswitch|kurento"

# Check ExternalSecrets sync
kubectl get externalsecret -n liveclasses
kubectl get secret mongodb-secret mongodb-keyfile -n liveclasses
```

## 📊 Expected Capacity After Scaling

**Before** (Current):
- 6 nodes × 2 CPU × ~3.7GB = ~12 CPU, ~22GB

**After** (After Terraform Apply):
- 6 nodes × 4 CPU × ~16GB = ~24 CPU, ~96GB

**Required** (With Reduced Requests):
- MongoDB: 6 CPU, 12GB
- FreeSWITCH: 6 CPU, 12GB (reduced from 12 CPU, 24GB)
- Kurento: 6 CPU, 12GB (reduced from 12 CPU, 24GB)
- BBB Web: ~1 CPU, 1GB
- BBB API: ~1 CPU, 1GB
- **Total**: ~20 CPU, ~38GB

**Result**: ✅ Sufficient capacity after scaling

## 🔄 Deployment Flow

1. **Terraform Apply** → Creates secrets + scales nodes
2. **ExternalSecrets Sync** → Secrets available in Kubernetes
3. **MongoDB Pods Start** → Once secrets are available
4. **BBB Images Built/Pushed** → Once images are in ECR
5. **BBB Pods Start** → Once images are available
6. **FreeSWITCH/Kurento Pods Start** → Once nodes have capacity

## 🚨 Current Blockers

1. **Terraform State Lock**: Need to wait for lock to release or force unlock
2. **BBB Images**: Need to build/push images to ECR
3. **MongoDB Secrets**: Waiting for Terraform to create them

## 📝 Notes

- All manifests are deployed and ready
- Resource requests have been optimized
- StorageClass issue resolved
- Cluster scaling configuration ready
- Just waiting for Terraform apply and BBB images

