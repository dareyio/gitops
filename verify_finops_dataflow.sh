#!/bin/bash

# FinOps Dashboard Data Flow Verification Script
# This script verifies the entire data flow from AWS Cost Exporter to Grafana Dashboard

set -e

echo "=========================================="
echo "FinOps Dashboard Data Flow Verification"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Context (default to ops)
CONTEXT="${1:-ops}"
echo "Using Kubernetes context: $CONTEXT"
echo ""

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# Function to check if command exists
check_command() {
    if command -v $1 &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check prerequisites
echo "1. Checking Prerequisites..."
if ! check_command kubectl; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi
print_status 0 "kubectl found"

if ! check_command curl; then
    echo -e "${RED}Error: curl not found${NC}"
    exit 1
fi
print_status 0 "curl found"
echo ""

# Check exporter pod
echo "2. Checking AWS Cost Exporter Pod..."
EXPORTER_POD=$(kubectl get pods -n finops --context=$CONTEXT -l app=aws-cost-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$EXPORTER_POD" ]; then
    print_status 1 "Exporter pod not found in finops namespace"
    echo "  Run: kubectl get pods -n finops --context=$CONTEXT"
else
    print_status 0 "Exporter pod found: $EXPORTER_POD"
    
    # Check pod status
    POD_STATUS=$(kubectl get pod -n finops --context=$CONTEXT $EXPORTER_POD -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" = "Running" ]; then
        print_status 0 "Pod status: $POD_STATUS"
    else
        print_status 1 "Pod status: $POD_STATUS (expected: Running)"
    fi
fi
echo ""

# Check exporter service
echo "3. Checking AWS Cost Exporter Service..."
SERVICE_EXISTS=$(kubectl get svc -n finops --context=$CONTEXT aws-cost-exporter -o name 2>/dev/null || echo "")
if [ -z "$SERVICE_EXISTS" ]; then
    print_status 1 "Service aws-cost-exporter not found in finops namespace"
else
    print_status 0 "Service aws-cost-exporter found"
    
    # Check service endpoints
    ENDPOINTS=$(kubectl get endpoints -n finops --context=$CONTEXT aws-cost-exporter -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
    if [ -z "$ENDPOINTS" ]; then
        print_status 1 "Service has no endpoints"
    else
        print_status 0 "Service has endpoints"
    fi
fi
echo ""

# Check ServiceMonitor
echo "4. Checking ServiceMonitor..."
SERVICEMONITOR_EXISTS=$(kubectl get servicemonitor -n finops --context=$CONTEXT aws-cost-exporter -o name 2>/dev/null || echo "")
if [ -z "$SERVICEMONITOR_EXISTS" ]; then
    print_status 1 "ServiceMonitor aws-cost-exporter not found in finops namespace"
else
    print_status 0 "ServiceMonitor aws-cost-exporter found"
    
    # Check labels
    LABELS=$(kubectl get servicemonitor -n finops --context=$CONTEXT aws-cost-exporter -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "{}")
    if echo "$LABELS" | grep -q "release.*kube-prometheus-stack"; then
        print_status 0 "ServiceMonitor has correct labels (release: kube-prometheus-stack)"
    else
        print_status 1 "ServiceMonitor missing label: release: kube-prometheus-stack"
    fi
fi
echo ""

# Check exporter metrics endpoint
echo "5. Checking Exporter Metrics Endpoint..."
if [ -z "$EXPORTER_POD" ]; then
    print_status 1 "Cannot check metrics - pod not found"
else
    # Try to port-forward and check metrics
    kubectl port-forward -n finops --context=$CONTEXT svc/aws-cost-exporter 8080:8080 > /tmp/finops-pf.log 2>&1 &
    PF_PID=$!
    sleep 3
    
    if kill -0 $PF_PID 2>/dev/null; then
        METRICS_RESPONSE=$(curl -s http://localhost:8080/metrics 2>/dev/null || echo "")
        if [ -z "$METRICS_RESPONSE" ]; then
            print_status 1 "Metrics endpoint not responding"
        else
            # Check for expected metrics
            if echo "$METRICS_RESPONSE" | grep -q "aws_cost_exporter_current_month_cost"; then
                print_status 0 "Metrics endpoint responding with expected metrics"
                
                # Count metrics
                METRIC_COUNT=$(echo "$METRICS_RESPONSE" | grep -c "^aws_cost_exporter" || echo "0")
                echo "  Found $METRIC_COUNT aws_cost_exporter metrics"
            else
                print_status 1 "Metrics endpoint responding but missing expected metrics"
            fi
        fi
        kill $PF_PID 2>/dev/null || true
        wait $PF_PID 2>/dev/null || true
    else
        print_status 1 "Failed to port-forward to metrics endpoint"
    fi
fi
echo ""

# Check Prometheus targets
echo "6. Checking Prometheus Targets..."
PROM_POD=$(kubectl get pods -n monitoring --context=$CONTEXT -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$PROM_POD" ]; then
    print_status 1 "Prometheus pod not found in monitoring namespace"
else
    print_status 0 "Prometheus pod found: $PROM_POD"
    
    # Port-forward to Prometheus
    kubectl port-forward -n monitoring --context=$CONTEXT svc/kube-prometheus-stack-prometheus 9091:9090 > /tmp/prom-pf.log 2>&1 &
    PROM_PF_PID=$!
    sleep 3
    
    if kill -0 $PROM_PF_PID 2>/dev/null; then
        # Check targets
        TARGETS_RESPONSE=$(curl -s "http://localhost:9091/api/v1/targets" 2>/dev/null || echo "")
        if [ -z "$TARGETS_RESPONSE" ]; then
            print_status 1 "Cannot query Prometheus targets API"
        else
            # Check if aws-cost-exporter target exists
            if echo "$TARGETS_RESPONSE" | grep -q "aws-cost-exporter"; then
                print_status 0 "Prometheus has discovered aws-cost-exporter target"
                
                # Check target health
                TARGET_HEALTH=$(echo "$TARGETS_RESPONSE" | grep -A 5 "aws-cost-exporter" | grep -o '"health":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
                if [ "$TARGET_HEALTH" = "up" ]; then
                    print_status 0 "Target health: $TARGET_HEALTH"
                else
                    print_status 1 "Target health: $TARGET_HEALTH (expected: up)"
                fi
            else
                print_status 1 "Prometheus has not discovered aws-cost-exporter target"
            fi
        fi
        kill $PROM_PF_PID 2>/dev/null || true
        wait $PROM_PF_PID 2>/dev/null || true
    else
        print_status 1 "Failed to port-forward to Prometheus"
    fi
fi
echo ""

# Check Prometheus metrics
echo "7. Checking Prometheus Metrics..."
if [ -z "$PROM_POD" ]; then
    print_status 1 "Cannot check metrics - Prometheus pod not found"
else
    kubectl port-forward -n monitoring --context=$CONTEXT svc/kube-prometheus-stack-prometheus 9092:9090 > /tmp/prom-metrics-pf.log 2>&1 &
    PROM_METRICS_PF_PID=$!
    sleep 3
    
    if kill -0 $PROM_METRICS_PF_PID 2>/dev/null; then
        # Query for aws_cost_exporter metrics
        METRIC_QUERY=$(curl -s "http://localhost:9092/api/v1/query?query=aws_cost_exporter_current_month_cost" 2>/dev/null || echo "")
        if [ -z "$METRIC_QUERY" ]; then
            print_status 1 "Cannot query Prometheus metrics API"
        else
            # Check if metric exists
            if echo "$METRIC_QUERY" | grep -q '"result":\[{"metric"' || echo "$METRIC_QUERY" | grep -q '"result":\[\]'; then
                RESULT_COUNT=$(echo "$METRIC_QUERY" | grep -o '"result":\[[^]]*\]' | grep -o '{"metric"' | wc -l || echo "0")
                if [ "$RESULT_COUNT" -gt 0 ]; then
                    print_status 0 "Prometheus has metrics: aws_cost_exporter_current_month_cost"
                else
                    print_status 1 "Prometheus query returned no results"
                fi
            else
                print_status 1 "Unexpected response from Prometheus"
            fi
        fi
        kill $PROM_METRICS_PF_PID 2>/dev/null || true
        wait $PROM_METRICS_PF_PID 2>/dev/null || true
    else
        print_status 1 "Failed to port-forward to Prometheus"
    fi
fi
echo ""

# Check Thanos Query
echo "8. Checking Thanos Query..."
THANOS_POD=$(kubectl get pods -n monitoring --context=$CONTEXT -l app.kubernetes.io/name=thanos,app.kubernetes.io/component=query -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$THANOS_POD" ]; then
    print_status 1 "Thanos Query pod not found in monitoring namespace"
else
    print_status 0 "Thanos Query pod found: $THANOS_POD"
    
    # Port-forward to Thanos Query
    kubectl port-forward -n monitoring --context=$CONTEXT svc/thanos-query 9093:9090 > /tmp/thanos-pf.log 2>&1 &
    THANOS_PF_PID=$!
    sleep 3
    
    if kill -0 $THANOS_PF_PID 2>/dev/null; then
        # Query Thanos for metrics
        THANOS_QUERY=$(curl -s "http://localhost:9093/api/v1/query?query=aws_cost_exporter_current_month_cost" 2>/dev/null || echo "")
        if [ -z "$THANOS_QUERY" ]; then
            print_status 1 "Cannot query Thanos Query API"
        else
            # Check if metric exists
            if echo "$THANOS_QUERY" | grep -q '"result":\[{"metric"' || echo "$THANOS_QUERY" | grep -q '"result":\[\]'; then
                RESULT_COUNT=$(echo "$THANOS_QUERY" | grep -o '"result":\[[^]]*\]' | grep -o '{"metric"' | wc -l || echo "0")
                if [ "$RESULT_COUNT" -gt 0 ]; then
                    print_status 0 "Thanos Query has metrics: aws_cost_exporter_current_month_cost"
                else
                    print_status 1 "Thanos Query returned no results"
                fi
            else
                print_status 1 "Unexpected response from Thanos Query"
            fi
        fi
        kill $THANOS_PF_PID 2>/dev/null || true
        wait $THANOS_PF_PID 2>/dev/null || true
    else
        print_status 1 "Failed to port-forward to Thanos Query"
    fi
fi
echo ""

# Check exporter logs for errors
echo "9. Checking Exporter Logs..."
if [ -z "$EXPORTER_POD" ]; then
    print_status 1 "Cannot check logs - pod not found"
else
    LOGS=$(kubectl logs -n finops --context=$CONTEXT $EXPORTER_POD --tail=50 2>/dev/null || echo "")
    if echo "$LOGS" | grep -qi "error\|exception\|traceback"; then
        print_status 1 "Exporter logs contain errors"
        echo "  Recent errors:"
        echo "$LOGS" | grep -i "error\|exception\|traceback" | tail -3 | sed 's/^/    /'
    else
        print_status 0 "No errors found in exporter logs"
    fi
fi
echo ""

# Summary
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "Next steps if issues found:"
echo "1. Check exporter pod logs: kubectl logs -n finops --context=$CONTEXT -l app=aws-cost-exporter"
echo "2. Check Prometheus targets: kubectl port-forward -n monitoring --context=$CONTEXT svc/kube-prometheus-stack-prometheus 9090:9090"
echo "3. Check ServiceMonitor: kubectl get servicemonitor -n finops --context=$CONTEXT aws-cost-exporter -o yaml"
echo "4. Check AWS IAM permissions for Cost Explorer API"
echo ""

