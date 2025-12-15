# Lab Resource Reconciliation Worker Implementation

## Overview
This document provides the implementation code for a background reconciliation worker that detects and cleans up orphaned Kubernetes resources (Services, Ingresses, ConfigMaps) when their corresponding Deployments are missing.

## Files to Add/Modify

### 1. Create: `app/services/reconciliation_worker.py`

```python
"""
Background worker for reconciling orphaned lab resources.
Scans Kubernetes namespaces for Services/Ingresses/ConfigMaps without matching Deployments
and cleans them up, updating Redis accordingly.
"""
import time
import threading
import logging
import os
import re
from typing import List, Dict, Optional
from kubernetes import client, config
from app.utils.redis_helper import get_redis_client

logger = logging.getLogger(__name__)

# Lab namespaces to scan
LAB_NAMESPACES = os.getenv(
    "RECONCILIATION_NAMESPACES",
    "jupyter-lab,ubuntu-lab,vscode-lab,postgresql-lab"
).split(",")

# Reconciliation interval in seconds (default: 5 minutes)
RECONCILIATION_INTERVAL = int(os.getenv("RECONCILIATION_INTERVAL", "300"))

# Enable/disable reconciliation
RECONCILIATION_ENABLED = os.getenv("RECONCILIATION_ENABLED", "true").lower() == "true"


class ReconciliationWorker:
    """Worker that reconciles orphaned lab resources in Kubernetes."""
    
    def __init__(self):
        self.running = False
        self.thread = None
        self.k8s_mode = os.getenv("K8S_MODE", "cluster")
        
        # Initialize Kubernetes client
        if self.k8s_mode == "local":
            config.load_kube_config()
        else:
            config.load_incluster_config()
        
        self.core_v1 = client.CoreV1Api()
        self.apps_v1 = client.AppsV1Api()
        self.networking_v1 = client.NetworkingV1Api()
        self.redis = get_redis_client()
        
        logger.info(f"ReconciliationWorker initialized (enabled={RECONCILIATION_ENABLED}, interval={RECONCILIATION_INTERVAL}s)")
    
    def extract_session_id(self, resource_name: str, lab_type: str) -> Optional[str]:
        """
        Extract session ID from resource name.
        Format: {lab_type}-service-{session_id} or {lab_type}-ingress-{session_id}
        """
        pattern = f"^{lab_type}-(?:service|ingress|config)-(.+)$"
        match = re.match(pattern, resource_name)
        if match:
            return match.group(1)
        return None
    
    def get_lab_type_from_service(self, service_name: str) -> Optional[str]:
        """Extract lab type from service name (e.g., 'jupyter-service-xxx' -> 'jupyter')."""
        match = re.match(r"^([^-]+)-service-.+$", service_name)
        if match:
            return match.group(1)
        return None
    
    def check_deployment_exists(self, namespace: str, deployment_name: str) -> bool:
        """Check if a deployment exists in the namespace."""
        try:
            self.apps_v1.read_namespaced_deployment(name=deployment_name, namespace=namespace)
            return True
        except client.exceptions.ApiException as e:
            if e.status == 404:
                return False
            raise
    
    def check_service_has_endpoints(self, namespace: str, service_name: str) -> bool:
        """Check if a service has any endpoints."""
        try:
            endpoints = self.core_v1.read_namespaced_endpoints(name=service_name, namespace=namespace)
            if endpoints.subsets:
                for subset in endpoints.subsets:
                    if subset.addresses:
                        return True
            return False
        except client.exceptions.ApiException as e:
            if e.status == 404:
                return False
            raise
    
    def cleanup_orphaned_resources(self, namespace: str, session_id: str, lab_type: str) -> Dict[str, bool]:
        """
        Clean up orphaned resources for a session.
        Returns dict with cleanup results.
        """
        results = {
            "service": False,
            "ingress": False,
            "configmap": False,
            "redis": False
        }
        
        # Delete service
        service_name = f"{lab_type}-service-{session_id}"
        try:
            self.core_v1.delete_namespaced_service(
                name=service_name,
                namespace=namespace
            )
            results["service"] = True
            logger.info(f"Deleted orphaned service: {service_name} in {namespace}")
        except client.exceptions.ApiException as e:
            if e.status != 404:
                logger.warning(f"Error deleting service {service_name}: {e}")
        
        # Delete ingress
        ingress_name = f"{lab_type}-ingress-{session_id}"
        try:
            self.networking_v1.delete_namespaced_ingress(
                name=ingress_name,
                namespace=namespace
            )
            results["ingress"] = True
            logger.info(f"Deleted orphaned ingress: {ingress_name} in {namespace}")
        except client.exceptions.ApiException as e:
            if e.status != 404:
                logger.warning(f"Error deleting ingress {ingress_name}: {e}")
        
        # Delete configmap
        configmap_name = f"{lab_type}-config-{session_id}"
        try:
            self.core_v1.delete_namespaced_config_map(
                name=configmap_name,
                namespace=namespace
            )
            results["configmap"] = True
            logger.info(f"Deleted orphaned configmap: {configmap_name} in {namespace}")
        except client.exceptions.ApiException as e:
            if e.status != 404:
                logger.warning(f"Error deleting configmap {configmap_name}: {e}")
        
        # Clean up Redis session data
        session_key = f"lab_session:{session_id}"
        try:
            self.redis.delete(session_key)
            results["redis"] = True
            logger.info(f"Deleted Redis session key: {session_key}")
        except Exception as e:
            logger.warning(f"Error deleting Redis key {session_key}: {e}")
        
        return results
    
    def reconcile_namespace(self, namespace: str) -> Dict[str, int]:
        """
        Reconcile orphaned resources in a namespace.
        Returns statistics about the reconciliation.
        """
        stats = {
            "services_checked": 0,
            "orphaned_found": 0,
            "cleaned_up": 0,
            "errors": 0
        }
        
        try:
            # List all services in the namespace
            services = self.core_v1.list_namespaced_service(namespace=namespace)
            
            for service in services.items:
                service_name = service.metadata.name
                stats["services_checked"] += 1
                
                # Extract lab type and session ID
                lab_type = self.get_lab_type_from_service(service_name)
                if not lab_type:
                    continue
                
                session_id = self.extract_session_id(service_name, lab_type)
                if not session_id:
                    continue
                
                # Check if deployment exists
                deployment_name = f"{lab_type}-lab-{session_id}"
                if self.check_deployment_exists(namespace, deployment_name):
                    continue  # Deployment exists, not orphaned
                
                # Check if service has endpoints (double-check it's truly orphaned)
                if self.check_service_has_endpoints(namespace, service_name):
                    logger.warning(
                        f"Service {service_name} has endpoints but no deployment - "
                        f"manual investigation needed"
                    )
                    continue
                
                # This is an orphaned resource - clean it up
                stats["orphaned_found"] += 1
                logger.info(
                    f"Found orphaned service: {service_name} "
                    f"(no deployment: {deployment_name})"
                )
                
                try:
                    cleanup_results = self.cleanup_orphaned_resources(
                        namespace, session_id, lab_type
                    )
                    if any(cleanup_results.values()):
                        stats["cleaned_up"] += 1
                        logger.info(
                            f"Cleaned up resources for session {session_id}: "
                            f"{cleanup_results}"
                        )
                except Exception as e:
                    stats["errors"] += 1
                    logger.error(f"Error cleaning up session {session_id}: {e}")
        
        except Exception as e:
            logger.error(f"Error reconciling namespace {namespace}: {e}")
            stats["errors"] += 1
        
        return stats
    
    def run_reconciliation_cycle(self):
        """Run a single reconciliation cycle across all lab namespaces."""
        if not RECONCILIATION_ENABLED:
            return
        
        logger.info("🔍 Starting lab resource reconciliation cycle...")
        
        total_stats = {
            "namespaces_checked": 0,
            "services_checked": 0,
            "orphaned_found": 0,
            "cleaned_up": 0,
            "errors": 0
        }
        
        for namespace in LAB_NAMESPACES:
            namespace = namespace.strip()
            if not namespace:
                continue
            
            logger.info(f"📦 Checking namespace: {namespace}")
            total_stats["namespaces_checked"] += 1
            
            try:
                stats = self.reconcile_namespace(namespace)
                total_stats["services_checked"] += stats["services_checked"]
                total_stats["orphaned_found"] += stats["orphaned_found"]
                total_stats["cleaned_up"] += stats["cleaned_up"]
                total_stats["errors"] += stats["errors"]
            except Exception as e:
                logger.error(f"Error processing namespace {namespace}: {e}")
                total_stats["errors"] += 1
        
        logger.info(
            f"📊 Reconciliation Summary: "
            f"namespaces={total_stats['namespaces_checked']}, "
            f"services_checked={total_stats['services_checked']}, "
            f"orphaned={total_stats['orphaned_found']}, "
            f"cleaned={total_stats['cleaned_up']}, "
            f"errors={total_stats['errors']}"
        )
    
    def worker_loop(self):
        """Main worker loop that runs reconciliation periodically."""
        logger.info("Reconciliation worker started")
        
        while self.running:
            try:
                self.run_reconciliation_cycle()
            except Exception as e:
                logger.error(f"Error in reconciliation cycle: {e}")
            
            # Sleep until next cycle
            for _ in range(RECONCILIATION_INTERVAL):
                if not self.running:
                    break
                time.sleep(1)
        
        logger.info("Reconciliation worker stopped")
    
    def start(self):
        """Start the reconciliation worker in a background thread."""
        if not RECONCILIATION_ENABLED:
            logger.info("Reconciliation worker is disabled")
            return
        
        if self.running:
            logger.warning("Reconciliation worker is already running")
            return
        
        self.running = True
        self.thread = threading.Thread(target=self.worker_loop, daemon=True)
        self.thread.start()
        logger.info("Reconciliation worker thread started")
    
    def stop(self):
        """Stop the reconciliation worker."""
        if not self.running:
            return
        
        self.running = False
        if self.thread:
            self.thread.join(timeout=10)
        logger.info("Reconciliation worker stopped")


# Global worker instance
_reconciliation_worker = None


def start_reconciliation_worker():
    """Start the global reconciliation worker."""
    global _reconciliation_worker
    
    if _reconciliation_worker is None:
        _reconciliation_worker = ReconciliationWorker()
    
    _reconciliation_worker.start()
    return _reconciliation_worker


def stop_reconciliation_worker():
    """Stop the global reconciliation worker."""
    global _reconciliation_worker
    
    if _reconciliation_worker:
        _reconciliation_worker.stop()
```

### 2. Modify: `app/main.py`

Add the import and startup hook:

```python
# Add to imports section (around line 20)
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
    
    # Start reconciliation worker (NEW)
    try:
        start_reconciliation_worker()
        logging.info("✅ Reconciliation worker started")
    except Exception as e:
        logging.error(f"Failed to start reconciliation worker: {e}")
    
    # ... rest of startup code ...
```

### 3. Add Environment Variables (Optional - for configuration)

Add to deployment.yaml or set as environment variables:

```yaml
env:
  - name: RECONCILIATION_ENABLED
    value: "true"
  - name: RECONCILIATION_INTERVAL
    value: "300"  # 5 minutes in seconds
  - name: RECONCILIATION_NAMESPACES
    value: "jupyter-lab,ubuntu-lab,vscode-lab,postgresql-lab"
```

## Testing

1. **Deploy the changes** to the lab-controller service
2. **Check logs** for reconciliation worker activity:
   ```bash
   kubectl -n lab-controller logs deploy/lab-controller | grep -i reconciliation
   ```
3. **Verify cleanup** by checking for orphaned resources:
   ```bash
   kubectl -n jupyter-lab get svc
   kubectl -n jupyter-lab get ingress
   ```
4. **Monitor Redis** to ensure session keys are cleaned up

## Migration from CronJob

Once the worker is proven stable:
1. Disable the CronJob by setting `suspend: true` in `lab-reconciliation-cronjob.yaml`
2. Or remove the CronJob entirely from kustomization.yaml
3. The worker will handle all reconciliation automatically

