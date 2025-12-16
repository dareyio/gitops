# Cluster Capacity Issues - Staging

## Current Cluster Status

- **Nodes**: 6 nodes
- **CPU per node**: 2 cores
- **Memory per node**: ~3.7GB
- **Total available**: ~12 CPU, ~22GB memory

## Required Resources

### MongoDB (StatefulSet, 3 replicas)

- **Per pod**: 2 CPU, 4GB memory
- **Total**: 6 CPU, 12GB memory

### FreeSWITCH (DaemonSet, 6 pods - one per node)

- **Per pod**: 2 CPU, 4GB memory
- **Total**: 12 CPU, 24GB memory

### Kurento Media Server (DaemonSet, 6 pods - one per node)

- **Per pod**: 2 CPU, 4GB memory
- **Total**: 12 CPU, 24GB memory

### BBB Web (Deployment, 2 replicas)

- **Per pod**: ~500m CPU, 512MB memory
- **Total**: ~1 CPU, 1GB memory

### BBB Native API (Deployment, 2 replicas)

- **Per pod**: ~500m CPU, 512MB memory
- **Total**: ~1 CPU, 1GB memory

### **Total Required**: ~32 CPU, ~64GB memory

## Gap Analysis

- **CPU Shortfall**: ~20 CPU cores
- **Memory Shortfall**: ~42GB

## Solutions

### Option 1: Scale Up Node Groups (Recommended)

Update Terraform to increase node instance size:

```hcl
# In terraform/environments/staging/workload-cluster.tf
# Update managed node group instance types
eks_managed_node_groups = {
  default = {
    instance_types = ["t3.xlarge"]  # 4 CPU, 16GB (instead of t3.small: 2 CPU, 2GB)
    min_size       = 3
    max_size       = 10
    desired_size   = 6
  }
}
```

**After update**:

- Run `terraform plan` to see changes
- Run `terraform apply` to scale nodes
- Wait for new nodes to join cluster
- Drain old nodes and remove them

### Option 2: Add More Nodes

Keep current instance size but add more nodes:

```hcl
desired_size = 10  # Add 4 more nodes
```

**After update**:

- Total capacity: 20 CPU, ~37GB (still insufficient for FreeSWITCH/Kurento)

### Option 3: Reduce Resource Requests (Temporary)

Reduce FreeSWITCH and Kurento resource requests to fit current cluster:

```yaml
# In freeswitch-daemonset.yaml and kurento-daemonset.yaml
resources:
  requests:
    cpu: 1000m # Reduce from 2000m
    memory: 2Gi # Reduce from 4Gi
  limits:
    cpu: 2000m # Reduce from 4000m
    memory: 4Gi # Reduce from 8Gi
```

**Note**: This may impact performance but allows deployment on current cluster.

### Option 4: Use Node Selectors (Dedicated Nodes)

Create dedicated node pool for media processing:

```hcl
eks_managed_node_groups = {
  default = {
    instance_types = ["t3.medium"]  # 2 CPU, 4GB
    min_size       = 3
    max_size       = 6
    desired_size   = 3
  }
  media = {
    instance_types = ["t3.xlarge"]  # 4 CPU, 16GB
    min_size       = 3
    max_size       = 6
    desired_size   = 3
    labels = {
      node-type = "media-processing"
    }
  }
}
```

Then update DaemonSets to use node selector:

```yaml
nodeSelector:
  node-type: media-processing
```

## Recommended Action

**Immediate**: Fix StorageClass and reduce resource requests temporarily to get pods running.

**Long-term**: Scale up to `t3.xlarge` instances (4 CPU, 16GB each) for 6 nodes = 24 CPU, 96GB total.

## StorageClass Issue

MongoDB is using `gp3` but cluster only has `gp2` and `gp2-csi`. Fixed in StatefulSet manifest.
