# Verification and CI/CD Trigger Guide

## 1. Verify GitHub Actions Secret Configuration

The GitHub Actions workflow requires the `AWS_ROLE_ARN` secret to be configured in the repository.

### Expected Secret Value:
```
arn:aws:iam::586794457112:role/prod-github-actions-dareyscore-role
```

### Verification Steps:

1. Go to: `https://github.com/dareyio/dareyscore/settings/secrets/actions`
2. Verify that `AWS_ROLE_ARN` secret exists
3. If missing, add it:
   - Click "New repository secret"
   - Name: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::586794457112:role/prod-github-actions-dareyscore-role`
   - Click "Add secret"

### Verify via Terraform Output:
```bash
cd terraform
terraform output github_actions_role_arn
```

Expected output: `arn:aws:iam::586794457112:role/prod-github-actions-dareyscore-role`

## 2. Verify IAM Permissions

The GitHub Actions role should have ECR push/pull permissions for `dareyscore/*` repositories.

### Verify via AWS CLI:
```bash
aws iam get-role-policy --role-name prod-github-actions-dareyscore-role --policy-name prod-github-actions-dareyscore-role-ecr-policy
```

The policy should allow:
- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:GetDownloadUrlForLayer`
- `ecr:BatchGetImage`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`

For resources: `arn:aws:ecr:eu-west-2:586794457112:repository/dareyscore/*`

## 3. Trigger CI/CD Pipeline

### Option A: Manual Trigger (Recommended for Testing)

1. Go to: `https://github.com/dareyio/dareyscore/actions`
2. Select workflow: "Darey Score CI/CD"
3. Click "Run workflow"
4. Select branch: `main`
5. Click "Run workflow"

### Option B: Push to Trigger

The workflow triggers automatically on:
- Push to `main` branch (when `services/api/**` or `services/worker/**` files change)
- Pull request to `main` branch
- Manual dispatch (`workflow_dispatch`)

To trigger via push:
```bash
cd darey-score/dareyscore
# Make a small change to trigger the workflow
echo "# CI/CD Trigger" >> .github/workflows/dareyscore-ci-cd.yml
git add .github/workflows/dareyscore-ci-cd.yml
git commit -m "chore: trigger CI/CD pipeline"
git push origin main
```

## 4. Monitor Pipeline Execution

1. Go to: `https://github.com/dareyio/dareyscore/actions`
2. Click on the running workflow
3. Monitor the following jobs:
   - `build-and-push-api`: Builds and pushes API Docker image
   - `build-and-push-worker`: Builds and pushes Worker Docker image
   - `test`: Runs test suite

## 5. Verify Images in ECR

After the pipeline completes successfully:

```bash
# List images in API repository
aws ecr describe-images --repository-name dareyscore/dareyscore-api --region eu-west-2

# List images in Worker repository
aws ecr describe-images --repository-name dareyscore/dareyscore-worker --region eu-west-2
```

You should see images tagged with:
- `latest`
- Git commit SHA (e.g., `abc123def456...`)

## 6. Force ArgoCD Sync

After images are available in ECR, force ArgoCD to sync:

```bash
kubectl annotate application dareyscore -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

Or via ArgoCD UI:
1. Go to ArgoCD UI
2. Select `dareyscore` application
3. Click "Refresh" → "Hard Refresh"
4. Click "Sync" if needed

## 7. Verify Pods Start Successfully

```bash
# Watch pods
kubectl get pods -n dareyscore -w

# Check pod logs if issues
kubectl logs -n dareyscore -l app=dareyscore-api --tail=50
kubectl logs -n dareyscore -l app=dareyscore-worker --tail=50
kubectl logs -n dareyscore postgres-0 --tail=50
```

Expected status:
- `dareyscore-api-*`: Running
- `dareyscore-worker-*`: Running
- `postgres-0`: Running
- `redis-0`: Running

## 8. Test API Endpoint

Once all pods are running:

```bash
# Test health endpoint
curl https://dareyscore.talentos.darey.io/health

# Expected response: {"status":"healthy"} or similar
```

