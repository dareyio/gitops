# Lab Resource Reconciliation Design

## Problem Statement

Lab sessions can leave orphaned Kubernetes resources (Services, Ingresses, ConfigMaps) when:
- Deployments are manually deleted
- Pods crash and deployments are not recreated
- Lab-controller service fails during cleanup
- Network issues prevent proper resource deletion

This results in:
- 503 errors for users trying to access labs
- DNS records pointing to non-existent backends
- Resource leaks in the cluster
- Stale Redis/database entries

## Current State

**Existing Cleanup Mechanisms:**
1. **Reactive cleanup** in `evaluate-linux-project` function - handles 404s from lab-controller
2. **Frontend cleanup** in `labController.ts` - cleans up expired sessions from client-side
3. **Manual cleanup** via `/labs/{session_id}/release` endpoint

**Missing:**
- Proactive reconciliation worker in lab-controller service
- Automatic detection of orphaned resources
- Redis/database synchronization after cleanup

## Temporary Solution (Implemented)

A Kubernetes CronJob (`lab-reconciliation-cronjob.yaml`) runs every 5 minutes to:
1. Scan all lab namespaces (jupyter-lab, ubuntu-lab, vscode-lab, postgresql-lab)
2. Find Services without matching Deployments
3. Verify Services have no endpoints
4. Delete orphaned Services, Ingresses, and ConfigMaps
5. Log reconciliation results

**Limitations:**
- Does not update Redis/database
- Does not notify lab-controller API
- Runs as external job, not integrated with service

## Recommended Long-term Solution

### Implementation in Lab-Controller Service

Add a background worker/goroutine to the lab-controller service that:

#### 1. Reconciliation Worker
```python
# Pseudo-code structure
class LabReconciliationWorker:
    def __init__(self, k8s_client, redis_client, db_client):
        self.k8s = k8s_client
        self.redis = redis_client
        self.db = db_client
        self.interval = 300  # 5 minutes
    
    async def run(self):
        while True:
            await self.reconcile_orphaned_resources()
            await asyncio.sleep(self.interval)
    
    async def reconcile_orphaned_resources(self):
        # 1. Get all services from lab namespaces
        # 2. For each service, check if deployment exists
        # 3. If no deployment and no endpoints:
        #    - Delete service, ingress, configmap
        #    - Update Redis (remove session keys)
        #    - Update database (mark session as stopped/cleaned)
        #    - Emit event/metrics
```

#### 2. Redis Synchronization
- Remove session keys from Redis when resources are cleaned
- Update session status in Redis cache
- Clean up any associated tokens

#### 3. Database Updates
- Mark lab sessions as `status: 'stopped'` with `cleanup_reason: 'orphaned_resource'`
- Set `cleanup_completed_at` timestamp
- Log reconciliation events for audit

#### 4. Health Checks
- Expose metrics for orphaned resources count
- Alert when orphaned resources exceed threshold
- Track reconciliation success/failure rates

#### 5. Configuration
Add environment variables:
- `RECONCILIATION_ENABLED=true`
- `RECONCILIATION_INTERVAL=300` (seconds)
- `RECONCILIATION_NAMESPACES=jupyter-lab,ubuntu-lab,vscode-lab,postgresql-lab`

## Migration Plan

1. **Phase 1 (Current)**: Deploy CronJob as temporary solution ✅
2. **Phase 2**: Implement reconciliation worker in lab-controller service
3. **Phase 3**: Add Redis/database synchronization
4. **Phase 4**: Remove CronJob once service worker is proven stable
5. **Phase 5**: Add monitoring/alerting for reconciliation metrics

## Notes

- The CronJob uses the same ServiceAccount (`lab-controller-sa`) as the main service, so it has all necessary RBAC permissions
- The CronJob is idempotent - safe to run multiple times
- Consider adding a mutex/lock in Redis to prevent concurrent reconciliation runs if implementing in service

