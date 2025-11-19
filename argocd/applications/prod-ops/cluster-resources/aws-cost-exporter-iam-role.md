# AWS Cost Exporter IAM Role Setup

## Required IAM Policy

Create an IAM role with the following policy to allow the cost exporter to access AWS Cost Explorer API and Budgets API.

### IAM Policy JSON

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CostExplorerReadOnly",
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetDimensionValues",
        "ce:GetUsage",
        "ce:GetCostForecast",
        "ce:GetReservationCoverage",
        "ce:GetReservationPurchaseRecommendation",
        "ce:GetReservationUtilization",
        "ce:GetRightsizingRecommendation",
        "ce:GetSavingsPlansCoverage",
        "ce:GetSavingsPlansUtilization",
        "ce:ListCostCategoryDefinitions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BudgetsReadOnly",
      "Effect": "Allow",
      "Action": [
        "budgets:ViewBudget",
        "budgets:DescribeBudgets",
        "budgets:DescribeBudgetPerformanceHistory"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchReadOnly",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics"
      ],
      "Resource": "*"
    }
  ]
}
```

## Steps to Create IAM Role

### 1. Create IAM Role

```bash
# Create trust policy for EKS service account
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::586794457112:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/YOUR_OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.eu-west-2.amazonaws.com/id/YOUR_OIDC_ID:sub": "system:serviceaccount:finops:aws-cost-exporter",
          "oidc.eks.eu-west-2.amazonaws.com/id/YOUR_OIDC_ID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create the IAM role
aws iam create-role \
  --role-name darey-io-v2-lab-prod-ops-aws-cost-exporter-role \
  --assume-role-policy-document file://trust-policy.json \
  --description "IAM role for AWS Cost Exporter in OPS cluster"

# Attach the policy (create policy first)
aws iam put-role-policy \
  --role-name darey-io-v2-lab-prod-ops-aws-cost-exporter-role \
  --policy-name CostExporterPolicy \
  --policy-document file://cost-exporter-policy.json
```

### 2. Get OIDC Provider ID

```bash
# Get your EKS cluster OIDC provider ID
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5
```

### 3. Alternative: Use AWS Console

1. Go to IAM Console → Roles → Create Role
2. Select "Web Identity" as trusted entity
3. Choose your EKS OIDC provider
4. Set audience to `sts.amazonaws.com`
5. Add condition: `StringEquals` with key `system:serviceaccount:finops:aws-cost-exporter`
6. Attach the policy above
7. Name: `darey-io-v2-lab-prod-ops-aws-cost-exporter-role`

## Verify Role

```bash
# Check if role exists
aws iam get-role --role-name darey-io-v2-lab-prod-ops-aws-cost-exporter-role

# List attached policies
aws iam list-role-policies --role-name darey-io-v2-lab-prod-ops-aws-cost-exporter-role
```

## Notes

- Replace `YOUR_OIDC_ID` with your actual EKS OIDC provider ID
- Replace `YOUR_CLUSTER_NAME` with your actual EKS cluster name
- The role ARN should match: `arn:aws:iam::586794457112:role/darey-io-v2-lab-prod-ops-aws-cost-exporter-role`
- Ensure Cost Explorer API is enabled in your AWS account (it's enabled by default but may take 24 hours to activate)

