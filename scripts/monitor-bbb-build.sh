#!/bin/bash
set -e

echo "=== Monitoring BBB Build Workflow ==="
echo ""
echo "This will check status every 30 seconds..."
echo "Build typically takes 20-40 minutes"
echo ""

for i in {1..80}; do
    RUN=$(gh run list --workflow=build-bbb-images.yml --limit 1 --json status,conclusion,databaseId,createdAt --jq '.[0]' 2>/dev/null || echo "null")
    
    if [ "$RUN" = "null" ] || [ -z "$RUN" ]; then
        echo "[$(date +%H:%M:%S)] ($i/80) Waiting for workflow to start..."
        sleep 30
        continue
    fi
    
    STATUS=$(echo $RUN | jq -r '.status')
    CONCLUSION=$(echo $RUN | jq -r '.conclusion // "N/A"')
    RUN_ID=$(echo $RUN | jq -r '.databaseId')
    
    echo "[$(date +%H:%M:%S)] ($i/80) Status: $STATUS, Conclusion: $CONCLUSION"
    
    if [ "$STATUS" = "completed" ]; then
        if [ "$CONCLUSION" = "success" ]; then
            echo ""
            echo "✅✅✅ Workflow completed successfully! ✅✅✅"
            echo ""
            echo "Verifying images in ECR..."
            aws ecr describe-images --repository-name liveclasses --region eu-west-2 \
                --image-ids imageTag=bbb-web:3.0.4 imageTag=bbb-html5:3.0.4 2>&1 | head -15
            echo ""
            echo "Checking Kubernetes pods..."
            kubectl get pods -n liveclasses | grep -E "bbb-web|bbb-api"
            echo ""
            echo "Waiting 60 seconds for pods to pull images..."
            sleep 60
            echo ""
            echo "Final pod status:"
            kubectl get pods -n liveclasses | grep -E "bbb-web|bbb-api"
            break
        else
            echo ""
            echo "❌ Workflow failed. Showing last 50 lines of logs..."
            gh run view $RUN_ID --log 2>&1 | tail -50
            exit 1
        fi
    fi
    
    sleep 30
done

