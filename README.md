# GitOps Repository

ArgoCD GitOps repository for managing Kubernetes applications across EKS clusters.

## Overview

This repository contains ArgoCD Application definitions and Kubernetes manifests for deploying applications to production EKS clusters using GitOps principles with an ops/workload architecture.

## Structure

```
gitops/
├── argocd/
│   ├── applications/
│   │   ├── prod-ops/           # Operations cluster applications
│   │   │   ├── applications/   # ArgoCD Application definitions
│   │   │   ├── cluster-resources/  # Cluster-level resources
│   │   │   └── dashboards/     # Grafana dashboards
│   │   ├── prod-workload/      # Workload cluster applications
│   │   │   ├── applications/   # ArgoCD Application definitions
│   │   │   ├── cluster-resources/  # Cluster-level resources
│   │   │   ├── dareyscore/     # DareyScore application manifests
│   │   │   ├── liveclasses/    # LiveClasses application manifests
│   │   │   ├── lab-controller/ # Lab Controller application manifests
│   │   │   └── dashboards/     # Grafana dashboards
│   │   ├── staging-ops/        # Staging operations cluster
│   │   └── staging-workload/   # Staging workload cluster
│   └── bootstrap/              # Bootstrap applications
│       ├── prod-ops.yaml       # Operations cluster bootstrap
│       ├── prod-workload.yaml  # Workload cluster bootstrap
│       ├── staging-ops.yaml    # Staging operations bootstrap
│       └── staging-workload.yaml # Staging workload bootstrap
├── ops/
│   └── dns-targets.yaml        # DNS routing configuration
└── README.md
```

## Ops/Workload Architecture

The infrastructure uses a separation of concerns approach:

- **Ops Cluster**: Manages ArgoCD, monitoring, and operational tools
- **Workload Cluster**: Runs application workloads (DareyScore, LiveClasses, Lab Controller)
- **DNS Routing**: Customer-facing domains route to workload cluster via External-DNS

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

## Cluster Management

Applications are managed via ArgoCD:

- **Ops Cluster**: ArgoCD runs in the ops cluster and manages applications across all clusters
- **Workload Cluster**: Application workloads run in the workload cluster
- **Multi-Cluster**: ArgoCD in ops cluster can manage applications in both ops and workload clusters

## Customer-Facing DNS

The customer-facing domain `dareyscore.talentos.darey.io` is configured to:

- Point to the workload cluster's LoadBalancer (managed by External-DNS)
- Accept TLS certificates via cert-manager (Let's Encrypt)
- Route traffic to the workload cluster automatically

## ArgoCD Bootstrap

Bootstrap applications are defined in `argocd/bootstrap/`:

- `prod-ops.yaml` - Bootstrap application for operations cluster
- `prod-workload.yaml` - Bootstrap application for workload cluster
- `staging-ops.yaml` - Bootstrap application for staging operations cluster
- `staging-workload.yaml` - Bootstrap application for staging workload cluster

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
