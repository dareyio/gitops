# Next Steps for BBB Deployment Completion

## Current Status ✅

**Successfully Running (19 pods):**
- ✅ MongoDB: 3/3 pods Running (replica set needs initialization)
- ✅ FreeSWITCH: 6/6 pods Running
- ✅ Kurento: 6/6 pods Running  
- ✅ Custom BBB API: 2 pods Running
- ✅ Other services: 2 pods Running

**Blocking (4 pods):**
- ❌ BBB web: 2 pods ImagePullBackOff
- ❌ BBB native API: 2 pods ImagePullBackOff

## Action Plan

### Step 1: Initialize MongoDB Replica Set ⚠️ REQUIRED

MongoDB pods are running but the replica set is not initialized. This is required before BBB can connect.

**Option A: Use the existing init job (Recommended)**
```bash
kubectl apply -f argocd/applications/staging-workload/liveclasses/bbb/mongodb-init-job.yaml
kubectl wait --for=condition=complete job/mongodb-init-replicaset -n liveclasses --timeout=300s
kubectl logs -n liveclasses job/mongodb-init-replicaset
```

**Option B: Manual initialization**
```bash
kubectl exec -it mongodb-0 -n liveclasses -- mongosh --username="$(kubectl get secret mongodb-secrets -n liveclasses -o jsonpath='{.data.root-username}' | base64 -d)" --password="$(kubectl get secret mongodb-secrets -n liveclasses -o jsonpath='{.data.root-password}' | base64 -d)" --authenticationDatabase=admin --eval "rs.initiate({_id: 'bbb-rs', members: [{_id: 0, host: 'mongodb-0.mongodb.liveclasses.svc.cluster.local:27017'}, {_id: 1, host: 'mongodb-1.mongodb.liveclasses.svc.cluster.local:27017'}, {_id: 2, host: 'mongodb-2.mongodb.liveclasses.svc.cluster.local:27017'}]})"
```

**Verify:**
```bash
kubectl exec -n liveclasses mongodb-0 -- mongosh --eval "rs.status().ok" --quiet
# Should return: 1
```

### Step 2: Build BBB Images from Docker Repo 🐳

The BBB Docker repo at `/tmp/bbb-docker` needs to be properly set up with submodules and built.

**Prerequisites:**
1. Ensure submodules are initialized:
```bash
cd /tmp/bbb-docker
git submodule update --init --recursive
```

2. Set up environment (create `.env` file):
```bash
cd /tmp/bbb-docker
cp sample.env .env
# Edit .env and set:
# - BBB_BUILD_TAG=3.0.4
# - TAG_BBB=3.0.4
# - EXTERNAL_IPv4=<your-external-ip>
# - Other required variables
```

3. Build images:
```bash
cd /tmp/bbb-docker
./scripts/generate-compose
docker compose build bbb-web
docker compose build html5
```

**Note:** The BBB Docker repo uses a complex build system with:
- Multiple submodules (bigbluebutton, freeswitch, etc.)
- Build contexts and additional contexts
- Base images that need to be built first

**Alternative:** If building is too complex, consider:
- Using pre-built images from a BBB community registry (if available)
- Building images in CI/CD pipeline
- Using a simpler BBB deployment method

### Step 3: Push Images to ECR 📤

Once images are built locally:

```bash
# Tag images
docker tag <local-bbb-web-image> 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-web:3.0.4
docker tag <local-bbb-html5-image> 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-html5:3.0.4

# Login to ECR
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin 586794457112.dkr.ecr.eu-west-2.amazonaws.com

# Push images
docker push 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-web:3.0.4
docker push 586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-html5:3.0.4
```

### Step 4: Update Deployments (Already Done) ✅

The deployments are already configured to use ECR images:
- `bbb-web-deployment.yaml` → `586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-html5:3.0.4`
- `bbb-native-api-deployment.yaml` → `586794457112.dkr.ecr.eu-west-2.amazonaws.com/liveclasses/bbb-web:3.0.4`

Once images are in ECR, pods should automatically pull and start.

### Step 5: Verify Full Stack 🧪

After all pods are running:

```bash
# Check all pods
kubectl get pods -n liveclasses

# Test BBB API
curl https://streaming-stg.talentos.darey.io/bbb/api/health

# Test BBB native API
curl https://streaming-stg.talentos.darey.io/bigbluebutton/api

# Check MongoDB replica set
kubectl exec -n liveclasses mongodb-0 -- mongosh --eval "rs.status()"
```

## Summary

**Immediate Priority:**
1. ✅ Initialize MongoDB replica set (5 minutes)
2. ⚠️ Build BBB images (30-60 minutes, complex)
3. ⚠️ Push to ECR (5 minutes)
4. ✅ Verify deployment (5 minutes)

**Total Estimated Time:** 45-75 minutes

**Current Blockers:**
- MongoDB replica set not initialized (quick fix)
- BBB images need to be built from source (time-consuming)

**Recommendation:**
Start with MongoDB initialization (Step 1) as it's quick and required. Then tackle BBB image building, which may require additional research or alternative approaches if the build process is too complex.

