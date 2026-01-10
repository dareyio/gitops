# Staging Dashboards Migration

This directory contains staging-ops dashboards migrated to prod-ops.

**Note:** The dashboards in staging-ops and prod-ops are identical and query metrics by `cluster` labels. After Prometheus federation is configured with `source_cluster` labels for staging-workload and prod-workload, the existing dashboards in the parent directories will automatically display metrics from both environments.

Dashboards query using expressions like:

- `count(count by (cluster) (up))` - counts all clusters
- `sum(...) by (cluster)` - aggregates by cluster label

Once Prometheus federation is active with proper `source_cluster` labels, all dashboards will show data from both staging-workload and prod-workload clusters.

**Original location:** `argocd/applications/staging-ops/dashboards/`
**Migrated to:** `argocd/applications/prod-ops/dashboards/staging/`

The Grafana dashboards application is configured to recurse through all subdirectories, so these dashboards (if any staging-specific versions exist) will be automatically discovered.
