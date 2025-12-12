# BBB Image Build Workflow Setup

## Required GitHub Secrets

The workflow requires **ONE** of the following authentication methods:

### Option 1: OIDC (Recommended)

#### AWS_ROLE_ARN

**Purpose**: AWS IAM role ARN for OIDC authentication to push images to ECR

**How to configure:**
1. Go to: https://github.com/dareyio/gitops/settings/secrets/actions
2. Click "New repository secret"
3. Name: `AWS_ROLE_ARN`
4. Value: Your AWS IAM role ARN (e.g., `arn:aws:iam::586794457112:role/github-actions-role`)

**Note**: The IAM role must:
- Trust GitHub OIDC provider (see AWS documentation for setup)
- Have permissions to push to ECR repository `liveclasses`
- Be in region `eu-west-2`

### Option 2: Access Keys (Fallback)

If OIDC is not configured, you can use access keys:

#### AWS_ACCESS_KEY_ID
#### AWS_SECRET_ACCESS_KEY

**How to configure:**
1. Go to: https://github.com/dareyio/gitops/settings/secrets/actions
2. Add both secrets:
   - `AWS_ACCESS_KEY_ID`: Your AWS access key ID
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key

**Note**: The IAM user must have permissions to push to ECR repository `liveclasses` in region `eu-west-2`

## Workflow Status

Once the secret is configured:
- The workflow can be triggered manually via GitHub Actions
- Or it will run automatically on pushes to `main` (if workflow/script files change)
- Or on the weekly schedule (Mondays at 2 AM UTC)

## Monitoring

To monitor the workflow:
```bash
cd /Users/dare/Desktop/xterns/darey-new/gitops
gh run list --workflow=build-bbb-images.yml
gh run watch <run-id>
```

## Current Status

- ✅ Workflow file created
- ✅ Scripts committed
- ⚠️  Waiting for AWS_ROLE_ARN secret configuration

