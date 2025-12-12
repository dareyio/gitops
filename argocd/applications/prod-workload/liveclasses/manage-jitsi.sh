#!/bin/bash
# Script to manage Jitsi deployments based on ConfigMap
# Usage: ./manage-jitsi.sh [check|enable|disable]

set -e

NAMESPACE="liveclasses"
CONFIGMAP="liveclasses-config"

# Jitsi deployment names
JITSI_DEPLOYMENTS=(
  "jitsi-web"
  "jicofo"
  "jvb"
  "prosody"
  "jibri"
)

# Get jitsi_enabled value from ConfigMap
get_jitsi_status() {
  kubectl get configmap $CONFIGMAP -n $NAMESPACE -o jsonpath='{.data.jitsi_enabled}' 2>/dev/null || echo "true"
}

# Scale down Jitsi deployments
disable_jitsi() {
  echo "🔄 Disabling Jitsi deployments..."
  
  for deployment in "${JITSI_DEPLOYMENTS[@]}"; do
    if kubectl get deployment $deployment -n $NAMESPACE &>/dev/null; then
      echo "  ⬇️  Scaling down $deployment..."
      kubectl scale deployment $deployment -n $NAMESPACE --replicas=0
    else
      echo "  ⚠️  Deployment $deployment not found, skipping..."
    fi
  done
  
  echo "✅ Jitsi deployments scaled down"
}

# Scale up Jitsi deployments to their original replica counts
enable_jitsi() {
  echo "🔄 Enabling Jitsi deployments..."
  
  # Original replica counts from deployment files
  declare -A REPLICAS=(
    ["jitsi-web"]=1
    ["jicofo"]=1
    ["jvb"]=1
    ["prosody"]=1
    ["jibri"]=1
  )
  
  for deployment in "${JITSI_DEPLOYMENTS[@]}"; do
    if kubectl get deployment $deployment -n $NAMESPACE &>/dev/null; then
      REPLICA_COUNT=${REPLICAS[$deployment]:-1}
      echo "  ⬆️  Scaling up $deployment to $REPLICA_COUNT replicas..."
      kubectl scale deployment $deployment -n $NAMESPACE --replicas=$REPLICA_COUNT
    else
      echo "  ⚠️  Deployment $deployment not found, skipping..."
    fi
  done
  
  echo "✅ Jitsi deployments scaled up"
}

# Check current status
check_status() {
  JITSI_ENABLED=$(get_jitsi_status)
  echo "📊 Current Jitsi status: $JITSI_ENABLED"
  echo ""
  echo "Deployment status:"
  
  for deployment in "${JITSI_DEPLOYMENTS[@]}"; do
    if kubectl get deployment $deployment -n $NAMESPACE &>/dev/null; then
      REPLICAS=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.spec.replicas}')
      READY=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
      echo "  $deployment: $READY/$REPLICAS replicas"
    else
      echo "  $deployment: not found"
    fi
  done
}

# Main logic
ACTION=${1:-check}

case $ACTION in
  check)
    check_status
    ;;
  disable)
    disable_jitsi
    # Update ConfigMap
    kubectl patch configmap $CONFIGMAP -n $NAMESPACE --type merge -p '{"data":{"jitsi_enabled":"false"}}'
    echo "✅ ConfigMap updated: jitsi_enabled=false"
    ;;
  enable)
    enable_jitsi
    # Update ConfigMap
    kubectl patch configmap $CONFIGMAP -n $NAMESPACE --type merge -p '{"data":{"jitsi_enabled":"true"}}'
    echo "✅ ConfigMap updated: jitsi_enabled=true"
    ;;
  sync)
    # Sync based on current ConfigMap value
    JITSI_ENABLED=$(get_jitsi_status)
    if [ "$JITSI_ENABLED" = "false" ]; then
      disable_jitsi
    else
      enable_jitsi
    fi
    ;;
  *)
    echo "Usage: $0 [check|enable|disable|sync]"
    echo ""
    echo "Commands:"
    echo "  check   - Show current status (default)"
    echo "  enable  - Enable Jitsi (scale up deployments)"
    echo "  disable - Disable Jitsi (scale down deployments)"
    echo "  sync    - Sync deployments with ConfigMap value"
    exit 1
    ;;
esac

