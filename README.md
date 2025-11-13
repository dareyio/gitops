# GitOps Repository

ArgoCD GitOps repository for managing Kubernetes applications across EKS clusters.

## Overview

This repository contains ArgoCD Application definitions and Kubernetes manifests for deploying applications to production EKS clusters using GitOps principles with blue/green deployment support.

## Structure

```
gitops/
├── argocd/
│   ├── applications/
│   │   ├── prod-blue/          # Blue cluster applications
│   │   │   ├── applications/   # ArgoCD Application definitions
│   │   │   ├── cluster-resources/  # Cluster-level resources
│   │   │   ├── dareyscore/     # DareyScore application manifests
│   │   │   └── dashboards/     # Grafana dashboards
│   │   └── prod-green/         # Green cluster applications
│   │       ├── applications/  # ArgoCD Application definitions
│   │       ├── cluster-resources/  # Cluster-level resources
│   │       ├── dareyscore/     # DareyScore application manifests
│   │       └── dashboards/     # Grafana dashboards
│   └── bootstrap/              # Bootstrap applications
│       ├── prod-blue.yaml      # Blue cluster bootstrap
│       └── prod-green.yaml     # Green cluster bootstrap
├── ops/
│   ├── active-cluster.yaml     # Active cluster configuration
│   └── dns-targets.yaml        # DNS routing configuration
└── README.md
```

## Blue/Green Deployment

The infrastructure supports blue/green deployment with active cluster management:

- **Active Cluster**: Defined in `ops/active-cluster.yaml`
- **DNS Routing**: Customer-facing domain automatically routes to active cluster
- **Zero Downtime**: Switch clusters by updating active cluster and running Terraform

## Applications

### Core Infrastructure

- **NGINX Ingress Controller** - Ingress routing and LoadBalancer
- **External DNS** - Automatic DNS record management
- **External Secrets Operator** - Secrets management from AWS Secrets Manager
- **Cert-Manager** - TLS certificate management (Let's Encrypt)
- **ArgoCD Image Updater** - Automatic image updates from ECR

### Monitoring Stack

- **Prometheus** - Metrics collection
- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation
- **Tempo** - Distributed tracing
- **Alertmanager** - Alert routing

### Applications

- **DareyScore** - Scoring API and worker services

## Active Cluster Management

The active cluster is managed via `ops/active-cluster.yaml`:

```yaml
cluster: blue  # or green
last_updated: "2025-11-13T00:00:00Z"
```

When switching clusters:
1. Update `ops/active-cluster.yaml`
2. Run Terraform apply (updates DNS routing)
3. ArgoCD syncs applications to the new active cluster

## Customer-Facing DNS

The customer-facing domain `dareyscore.talentos.darey.io` is configured to:

- Point to the active cluster's LoadBalancer (managed by Terraform)
- Accept TLS certificates for both customer-facing and cluster-specific domains
- Route traffic to the active cluster automatically

## ArgoCD Bootstrap

Bootstrap applications are defined in `argocd/bootstrap/`:

- `prod-blue.yaml` - Bootstrap application for blue cluster
- `prod-green.yaml` - Bootstrap application for green cluster

These applications create the App-of-Apps pattern, managing all other applications.

## Application Structure

Each application directory contains:

- **ArgoCD Application YAML** - Application definition
- **Kubernetes Manifests** - Deployment, Service, Ingress, etc.
- **Configuration** - ConfigMaps, Secrets, ExternalSecrets
- **Monitoring** - ServiceMonitors, PrometheusRules

## Sync Policy

Applications use automated sync with:

- `prune: true` - Remove resources not in Git
- `selfHeal: true` - Automatically correct drift
- `syncOptions: [CreateNamespace=true]` - Auto-create namespaces

## Image Updates

ArgoCD Image Updater automatically:

- Monitors ECR for new image tags
- Updates deployment manifests
- Commits changes back to Git
- Triggers ArgoCD sync

## Secrets Management

Secrets are managed via External Secrets Operator:

- **Source**: AWS Secrets Manager
- **Sync**: Automatic sync to Kubernetes secrets
- **Rotation**: Managed by AWS Secrets Manager

## TLS Certificates

Certificates are managed by cert-manager:

- **Issuer**: Let's Encrypt (production and staging)
- **Challenge**: DNS-01 via Route53
- **Auto-renewal**: Automatic certificate renewal

## Monitoring

All applications include:

- **ServiceMonitors** - Prometheus metrics scraping
- **PrometheusRules** - Alerting rules
- **Grafana Dashboards** - Visualization

## License

Proprietary - Internal use only
