# Prometheus Federation Setup

## Overview

This document describes the Prometheus federation architecture that enables the Application Errors dashboard to query metrics from all clusters (blue, green, and ops) via a single Prometheus instance in the ops cluster.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Blue/Green Clusters                           │
│                                                                   │
│  Applications (dareyscore, lab-controller, liveclasses)         │
│         ↓                                                        │
│  Expose HTTP metrics (/metrics endpoint)                        │
│         ↓                                                        │
│  Blue/Green Prometheus (scrapes applications)                   │
│         ↓                                                        │
│  Ingress (prometheus-blue.talentos.darey.io)                    │
│         ↓                                                        │
│  Security Group (allows only ops cluster)                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                        Ops Cluster                               │
│                                                                   │
│  Ops Prometheus (federates from blue/green)                      │
│         ↓                                                        │
│  Grafana Dashboard (queries ops Prometheus)                      │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Prometheus Ingress Resources

**Location:** 
- `argocd/applications/prod-blue/cluster-resources/prometheus-ingress.yaml`
- `argocd/applications/prod-green/cluster-resources/prometheus-ingress.yaml`

**Purpose:** Expose Prometheus instances in blue/green clusters via HTTPS Ingress.

**Configuration:**
- Hostname: `prometheus-blue.talentos.darey.io` / `prometheus-green.talentos.darey.io`
- TLS: Managed by cert-manager (Let's Encrypt)
- DNS: Managed by External-DNS
- Backend: `kube-prometheus-stack-prometheus` service on port 9090

**Deployment:**
Managed by ArgoCD `cluster-resources` applications in blue/green clusters. Resources are automatically synced when the applications sync.

### 2. Security Group Configuration

**Location:** `terraform/prometheus-federation-security.tf`

**Purpose:** Restrict access to Prometheus Ingress endpoints to only the ops cluster.

**Configuration:**
- **Source:** Ops cluster security group (`module.eks_cluster["ops"].cluster_security_group_id`)
- **Destination:** Blue/green cluster node security groups (`module.eks_cluster["blue|green"].node_security_group_id`)
- **Port:** 443 (HTTPS)
- **Protocol:** TCP

**Implementation:**
```hcl
resource "aws_security_group_rule" "ops_to_blue_prometheus" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.eks_cluster["ops"].cluster_security_group_id
  security_group_id        = module.eks_cluster["blue"].node_security_group_id
  description              = "Allow ops Prometheus to federate from blue Prometheus via Ingress LoadBalancer (port 443)"
}
```

**Note:** For NLB (Network Load Balancer), traffic flows from the LoadBalancer to the nodes, so we allow access to the node security groups rather than the LoadBalancer itself.

### 3. Federation Configuration

**Location:** `argocd/applications/prod-ops/applications/kube-prometheus-stack.yaml`

**Configuration:**
```yaml
additionalScrapeConfigs:
  - job_name: 'federate-blue'
    honor_labels: true
    metrics_path: '/federate'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    params:
      'match[]':
        - '{__name__=~".+"}'
    static_configs:
      - targets:
          - 'prometheus-blue.talentos.darey.io'
        labels:
          source_cluster: 'blue'
  - job_name: 'federate-green'
    # ... similar configuration for green
```

**How it works:**
1. Ops Prometheus scrapes `/federate` endpoint from blue/green Prometheus
2. The `/federate` endpoint returns all metrics matching the `match[]` parameter
3. Metrics are labeled with `source_cluster: blue|green` to identify their origin
4. All metrics are stored in ops Prometheus with 30-day retention

### 4. Monitoring and Alerting

**Location:** `argocd/applications/prod-ops/cluster-resources/prometheusrule-federation-health.yaml`

**Alerts:**
1. **PrometheusFederationDown**: Federation target is down for >5 minutes
2. **PrometheusFederationScrapeErrors**: Scrape errors detected
3. **PrometheusFederationNoMetrics**: No HTTP metrics received for >10 minutes
4. **PrometheusFederationHighLatency**: Scrape latency >120 seconds

## Deployment Steps

### 1. Deploy Ingress Resources

Ingress resources are automatically deployed when ArgoCD syncs the `cluster-resources` applications:

```bash
# Verify cluster-resources apps are synced
kubectl get application cluster-resources -n argocd --context=ops

# Verify Ingress resources are created
kubectl get ingress -n monitoring --context=blue
kubectl get ingress -n monitoring --context=green
```

### 2. Apply Security Group Rules

```bash
cd terraform
terraform plan  # Review changes
terraform apply # Apply security group rules
```

### 3. Verify DNS and Certificates

```bash
# Check DNS records
dig prometheus-blue.talentos.darey.io
dig prometheus-green.talentos.darey.io

# Check TLS certificates
kubectl get certificate -n monitoring --context=blue
kubectl get certificate -n monitoring --context=green
```

### 4. Verify Federation Targets

```bash
# Port-forward to ops Prometheus
kubectl port-forward -n monitoring --context=ops svc/kube-prometheus-stack-prometheus 9090:9090

# Visit http://localhost:9090/targets
# Look for:
# - federate-blue (should be UP)
# - federate-green (should be UP)
```

### 5. Verify Federated Metrics

```bash
# Query for federated metrics
curl 'http://localhost:9090/api/v1/query?query={__name__=~"http_request.*|http_requests_total",source_cluster=~"blue|green"}'
```

### 6. Test Dashboard

1. Open Grafana: `https://grafana-ops.talentos.darey.io`
2. Navigate to "Application Errors" dashboard
3. Verify panels show data (not "No data")

## Troubleshooting

### Issue: Federation targets show DOWN

**Possible causes:**
1. Ingress resources not deployed
2. DNS records not created
3. TLS certificates not issued
4. Security group rules not applied
5. Network connectivity issues

**Debugging:**
```bash
# Check Ingress status
kubectl describe ingress prometheus-ingress -n monitoring --context=blue

# Check DNS
dig prometheus-blue.talentos.darey.io

# Check certificates
kubectl describe certificate prometheus-blue-tls -n monitoring --context=blue

# Check security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*eks*" --query 'SecurityGroups[*].[GroupId,GroupName]' --output table

# Test connectivity from ops cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never --context=ops -- curl -k https://prometheus-blue.talentos.darey.io/federate?match[]=up
```

### Issue: No metrics federated

**Possible causes:**
1. Applications not exposing metrics
2. ServiceMonitors/PodMonitors not configured
3. Federation scrape config incorrect
4. Metrics filtered out by match[] parameter

**Debugging:**
```bash
# Check if metrics exist in blue/green Prometheus
kubectl port-forward -n monitoring --context=blue svc/kube-prometheus-stack-prometheus 9090:9090
curl 'http://localhost:9090/api/v1/query?query=http_request_duration_seconds_count'

# Check federation scrape config
kubectl get prometheus kube-prometheus-stack-prometheus -n monitoring --context=ops -o yaml | grep -A 20 additionalScrapeConfigs

# Check federation target errors
kubectl logs -n monitoring --context=ops -l app.kubernetes.io/name=prometheus | grep federate
```

### Issue: Security group rules not working

**Possible causes:**
1. Wrong security group IDs
2. Rules not applied
3. NLB not forwarding to nodes correctly

**Debugging:**
```bash
# Verify security group rules exist
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=<node-security-group-id>" --query 'SecurityGroupRules[*].[SecurityGroupRuleId,IsEgress,FromPort,ToPort,ReferencedGroupInfo.GroupId]' --output table

# Test connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never --context=ops -- curl -k https://prometheus-blue.talentos.darey.io/federate?match[]=up
```

## Security Considerations

1. **TLS:** Federation uses HTTPS with TLS verification disabled (`insecure_skip_verify: true`). This is acceptable for internal federation but could be improved with proper certificate validation.

2. **Access Control:** Security groups restrict access to only the ops cluster. This prevents unauthorized access from other sources.

3. **Network Isolation:** Federation traffic flows through public Ingress endpoints. Consider using VPC peering or private endpoints for enhanced security in the future.

## Maintenance

### Updating Federation Configuration

1. Edit `argocd/applications/prod-ops/applications/kube-prometheus-stack.yaml`
2. Update `additionalScrapeConfigs` section
3. Commit and push changes
4. ArgoCD will automatically sync the changes
5. Prometheus will reload configuration automatically

### Updating Security Group Rules

1. Edit `terraform/prometheus-federation-security.tf`
2. Run `terraform plan` to review changes
3. Run `terraform apply` to apply changes

### Monitoring Federation Health

- Check Prometheus targets: `http://ops-prometheus:9090/targets`
- Check alerts: `http://ops-prometheus:9090/alerts`
- Review Grafana dashboard: Application Errors dashboard

## References

- [Prometheus Federation](https://prometheus.io/docs/prometheus/latest/federation/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [AWS Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/security-groups.html)
- [Terraform AWS Provider - Security Group Rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule)

