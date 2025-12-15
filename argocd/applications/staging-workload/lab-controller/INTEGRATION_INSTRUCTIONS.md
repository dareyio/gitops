# Integration Instructions for Reconciliation Worker

## Summary

The reconciliation worker has been implemented and is ready to be integrated into the lab-controller service. This document provides step-by-step instructions.

## Files Created

1. **`reconciliation_worker.py`** - The worker implementation (copy to `app/services/reconciliation_worker.py`)
2. **`RECONCILIATION_WORKER_IMPLEMENTATION.md`** - Detailed implementation guide
3. **`deployment.yaml`** - Updated with environment variables

## Integration Steps

### Step 1: Add the Worker File

Copy `reconciliation_worker.py` to your lab-controller repository:

```bash
# In lab-controller repository
cp reconciliation_worker.py app/services/reconciliation_worker.py
```

### Step 2: Update main.py

Add the import and startup hook to `app/main.py`:

```python
# Add to imports (around line 20, after warm_pool_worker import)
from app.services.reconciliation_worker import start_reconciliation_worker

# Add to @app.on_event("startup") function (after warm_pool_worker start)
@app.on_event("startup")
def on_startup():
    # ... existing code ...
    
    # Start warm pool worker (existing)
    try:
        start_warm_pool_worker()
    except Exception as e:
        logging.error(f"Failed to start warm pool worker: {e}")
    
    # Start reconciliation worker (NEW - add this)
    try:
        start_reconciliation_worker()
        logging.info("✅ Reconciliation worker started")
    except Exception as e:
        logging.error(f"Failed to start reconciliation worker: {e}")
    
    # ... rest of startup code ...
```

### Step 3: Deploy via GitOps

The environment variables have already been added to the deployment manifests:
- `RECONCILIATION_ENABLED=true`
- `RECONCILIATION_INTERVAL=300` (5 minutes)
- `RECONCILIATION_NAMESPACES=jupyter-lab,ubuntu-lab,vscode-lab,postgresql-lab`

Once you commit and push the code changes, ArgoCD will automatically deploy the new image.

### Step 4: Verify Deployment

After deployment, check the logs:

```bash
# Check if worker started
kubectl -n lab-controller logs deploy/lab-controller | grep -i "reconciliation worker"

# Monitor reconciliation cycles
kubectl -n lab-controller logs deploy/lab-controller -f | grep -i reconciliation
```

Expected log output:
```
ReconciliationWorker initialized (enabled=True, interval=300s)
Reconciliation worker thread started
🔍 Starting lab resource reconciliation cycle...
📦 Checking namespace: jupyter-lab
📊 Reconciliation Summary: namespaces=4, services_checked=22, orphaned=0, cleaned=0, errors=0
```

### Step 5: Test End-to-End

1. **Create an orphaned resource** (for testing):
   ```bash
   # Create a service without a deployment
   kubectl -n jupyter-lab create service clusterip test-orphan --tcp=80:8888
   ```

2. **Wait for reconciliation cycle** (up to 5 minutes)

3. **Verify cleanup**:
   ```bash
   kubectl -n jupyter-lab get svc test-orphan
   # Should show "NotFound"
   ```

4. **Check logs** for cleanup confirmation:
   ```bash
   kubectl -n lab-controller logs deploy/lab-controller | grep -i "orphaned\|cleaned"
   ```

### Step 6: Disable CronJob (Optional)

Once the worker is proven stable (after 24-48 hours), you can disable the CronJob:

```yaml
# In lab-reconciliation-cronjob.yaml
spec:
  suspend: true  # Add this line
```

Or remove it entirely from kustomization.yaml.

## Troubleshooting

### Worker not starting

Check logs for errors:
```bash
kubectl -n lab-controller logs deploy/lab-controller | grep -i "reconciliation\|error"
```

Common issues:
- Missing import: Ensure `reconciliation_worker.py` is in `app/services/`
- Redis connection: Check Redis secrets are configured
- Kubernetes permissions: Verify ServiceAccount has required RBAC

### Worker running but not cleaning up

1. Check if reconciliation is enabled:
   ```bash
   kubectl -n lab-controller get deploy lab-controller -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RECONCILIATION_ENABLED")].value}'
   ```

2. Verify namespaces are correct:
   ```bash
   kubectl -n lab-controller get deploy lab-controller -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RECONCILIATION_NAMESPACES")].value}'
   ```

3. Check worker logs for errors:
   ```bash
   kubectl -n lab-controller logs deploy/lab-controller | grep -A 5 "Error reconciling"
   ```

## Monitoring

The worker logs reconciliation statistics every cycle:
- `namespaces_checked`: Number of namespaces scanned
- `services_checked`: Total services examined
- `orphaned_found`: Services without deployments
- `cleaned_up`: Successfully cleaned resources
- `errors`: Errors encountered

Monitor these metrics to ensure the worker is functioning correctly.

