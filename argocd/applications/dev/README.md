# How Kubernetes Service Accounts Access AWS Resources (IRSA)

## 📚 Complete Guide to IAM Roles for Service Accounts

This guide explains how External Secrets Operator and External DNS authenticate with AWS to access resources like Secrets Manager and Route53, using **IAM Roles for Service Accounts (IRSA)**.

---

## 🔑 The Core Components

Think of this as a **trust chain** with 5 key players:

1. **EKS Cluster** - Your Kubernetes cluster
2. **OIDC Provider** - AWS's identity bridge (registered in IAM)
3. **Service Account** - Kubernetes identity for pods
4. **IAM Role** - AWS identity with permissions
5. **Pod** - The actual application (External Secrets Operator, External DNS)

---

## 🏗️ The Setup Phase (Infrastructure)

### Step 1: EKS Creates an OIDC Provider

When you create an EKS cluster, AWS automatically creates an **OIDC (OpenID Connect) Provider**. This acts like a "certificate authority" that can verify identities from your cluster.

```
EKS Cluster OIDC URL Example:
https://oidc.eks.eu-west-2.amazonaws.com/id/C95D284C309F53443A292B7006BE6E94
```

This OIDC provider is **registered in AWS IAM** so AWS can trust tokens signed by your cluster.

**How to view your OIDC provider:**
```bash
aws iam list-open-id-connect-providers
```

---

### Step 2: Terraform Creates the IAM Role

The Terraform module (`terraform/modules/iam-roles-for-service-accounts/`) creates an IAM role with a **trust policy** that looks like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::586794457112:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/[YOUR_ID]"
      },
      "Condition": {
        "StringEquals": {
          "[oidc-url]:sub": "system:serviceaccount:external-secrets-system:external-secrets-operator",
          "[oidc-url]:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

**What this means in plain English:**

- "I (the IAM role) trust the OIDC provider from your EKS cluster"
- "But ONLY if the request comes from the specific service account: `external-secrets-operator` in namespace `external-secrets-system`"
- "And the audience (aud) must be `sts.amazonaws.com`"

**Key security point:** The trust policy uses the `:sub` (subject) field to restrict which service account can assume this role. This is why we had to use `ClusterSecretStore` - the service account in `external-secrets-system` matches the trust policy.

---

### Step 3: Terraform Attaches Permissions

The IAM role needs permissions to perform actions. For External Secrets Operator:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:eu-west-2:586794457112:secret:*"
    }
  ]
}
```

For External DNS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/[ZONE_ID]"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:GetChange"
      ],
      "Resource": "*"
    }
  ]
}
```

---

### Step 4: Annotate the Service Account

In the Kubernetes service account, we add an annotation that links it to the IAM role:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-operator
  namespace: external-secrets-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::586794457112:role/prod-external-secrets-operator-role
```

This annotation is the **magic glue** that tells Kubernetes: "This service account should use this IAM role"

**In our setup:** This annotation is set via Helm values in `gitops/argocd/applications/prod/external-secrets-operator.yaml`:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::586794457112:role/prod-external-secrets-operator-role
```

---

## 🔄 The Runtime Flow (What Happens at Runtime)

Now let's walk through what happens when External Secrets Operator tries to access AWS Secrets Manager:

### Step 1: Pod Starts with Service Account

When the External Secrets Operator pod starts, it's assigned a service account:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: external-secrets-operator-xxx
  namespace: external-secrets-system
spec:
  serviceAccountName: external-secrets-operator  # <-- Uses this service account
```

---

### Step 2: Kubernetes Injects Credentials

Because the service account has the IAM role annotation, the **EKS Pod Identity Webhook** automatically:

1. **Mounts a projected volume** with a **JWT token** at:
   ```
   /var/run/secrets/eks.amazonaws.com/serviceaccount/token
   ```

2. **Sets environment variables**:
   ```bash
   AWS_ROLE_ARN=arn:aws:iam::586794457112:role/prod-external-secrets-operator-role
   AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
   ```

**The JWT Token Structure (conceptually):**

```json
{
  "header": {
    "alg": "RS256",
    "kid": "xyz"
  },
  "payload": {
    "iss": "https://oidc.eks.eu-west-2.amazonaws.com/id/[YOUR_ID]",
    "sub": "system:serviceaccount:external-secrets-system:external-secrets-operator",
    "aud": ["sts.amazonaws.com"],
    "exp": 1234567890,
    "iat": 1234567890
  },
  "signature": "..."
}
```

**Field meanings:**
- `iss` (issuer): Your EKS cluster's OIDC provider
- `sub` (subject): The exact service account this token represents
- `aud` (audience): Who this token is intended for (AWS STS)
- `exp` (expiration): When this token expires
- `signature`: Cryptographic signature by the cluster's private key

**You can inspect these in a running pod:**
```bash
# See the token file
kubectl exec -n external-secrets-system [pod-name] -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# See the environment variables
kubectl exec -n external-secrets-system [pod-name] -- env | grep AWS
```

---

### Step 3: External Secrets Makes AWS API Call

When External Secrets tries to read from Secrets Manager, the AWS SDK inside the pod automatically:

1. **Reads the JWT token** from `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
2. **Reads the role ARN** from the `AWS_ROLE_ARN` environment variable
3. **Calls AWS STS** (Security Token Service) API:
   ```
   POST https://sts.amazonaws.com/
   Action=AssumeRoleWithWebIdentity
   RoleArn=arn:aws:iam::586794457112:role/prod-external-secrets-operator-role
   WebIdentityToken=[JWT_TOKEN]
   RoleSessionName=external-secrets-session
   ```

---

### Step 4: AWS STS Validates the Token

AWS STS performs these security checks in order:

1. **Verifies the token signature** 
   - Uses the public key from the OIDC provider to verify the signature
   - This proves the token was signed by your EKS cluster

2. **Checks the issuer (`iss`)**
   - Confirms it matches the registered OIDC provider in IAM
   - Ensures the token came from your cluster, not somewhere else

3. **Checks the subject (`sub`)**
   - Verifies it matches the trust policy condition
   - Must be exactly: `system:serviceaccount:external-secrets-system:external-secrets-operator`
   - **This is why the namespace and service account name matter!**

4. **Checks the audience (`aud`)**
   - Must be `sts.amazonaws.com`
   - Prevents token reuse for other services

5. **Checks the token hasn't expired**
   - Tokens typically expire after 15 minutes to 1 hour

**If all checks pass**, STS returns **temporary AWS credentials**:

```json
{
  "Credentials": {
    "AccessKeyId": "ASIA...",
    "SecretAccessKey": "...",
    "SessionToken": "...",
    "Expiration": "2024-01-01T12:00:00Z"
  },
  "AssumedRoleUser": {
    "AssumedRoleId": "AROA...:external-secrets-session",
    "Arn": "arn:aws:sts::586794457112:assumed-role/prod-external-secrets-operator-role/external-secrets-session"
  }
}
```

These are **real, temporary AWS credentials** that work just like access keys, but they:
- Expire automatically (typically after 1 hour)
- Are rotated automatically when they expire
- Can't be extracted from the cluster (they're generated on-demand)

---

### Step 5: External Secrets Uses Temporary Credentials

Now the External Secrets Operator pod has **real AWS credentials**! It uses them to call AWS Secrets Manager:

```
GET https://secretsmanager.eu-west-2.amazonaws.com/
Action: GetSecretValue
SecretId: test-secrets
Authorization: AWS4-HMAC-SHA256 Credential=ASIA.../...
X-Amz-Security-Token: [SessionToken]
```

AWS Secrets Manager validates:
1. ✅ Are these credentials valid?
2. ✅ Does this role have permission to read secrets? (checks IAM policy)
3. ✅ Does the secret exist?

Then returns the secret data as JSON:

```json
{
  "SecretString": "{\"environment\":\"prod\",\"department\":\"IT\"}"
}
```

External Secrets Operator then creates a Kubernetes secret with this data!

---

## 🔐 Security Benefits

This approach is **much more secure** than using long-lived access keys:

| Traditional Access Keys | IRSA (This Approach) |
|------------------------|----------------------|
| Long-lived (years) | Short-lived (1 hour) |
| Manual rotation needed | Automatic rotation |
| Can be leaked/stolen | Can't extract from cluster |
| Hard to audit who used them | CloudTrail shows exact pod |
| Stored in secrets/env vars | Generated on-demand |
| Broad permissions often | Fine-grained per service account |

**Additional Security Features:**

1. **No secrets to manage** - No access keys to store or rotate
2. **Automatic expiration** - Credentials expire and are refreshed automatically
3. **Fine-grained control** - Only specific service accounts can assume specific roles
4. **Namespace isolation** - Service accounts in different namespaces can have different permissions
5. **Audit trail** - CloudTrail logs every `AssumeRoleWithWebIdentity` call with the service account identity
6. **Principle of least privilege** - Each service account gets only the permissions it needs

---

## 📊 Visual Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS Account (586794457112)                          │
│                                                                              │
│  ┌──────────────────────┐         ┌─────────────────────────────┐          │
│  │   IAM OIDC Provider  │         │   IAM Role                  │          │
│  │   (Registered)       │         │   prod-external-secrets-    │          │
│  │                      │◄────────│   operator-role             │          │
│  │   Issuer:            │ Trusts  │                             │          │
│  │   oidc.eks.eu-west-2 │         │   Trust Policy:             │          │
│  │   .amazonaws.com/... │         │   - Federated: OIDC         │          │
│  │                      │         │   - Condition: sub =        │          │
│  └──────────────────────┘         │     system:serviceaccount:  │          │
│                                    │     external-secrets-system │          │
│                                    │     :external-secrets-      │          │
│                                    │     operator                │          │
│                                    └───────────┬─────────────────┘          │
│                                                │                             │
│                                                │ Has Policy                  │
│                                                ▼                             │
│                                    ┌───────────────────────────┐            │
│                                    │  IAM Policy               │            │
│                                    │  - secretsmanager:        │            │
│                                    │    GetSecretValue         │            │
│                                    │  - secretsmanager:        │            │
│                                    │    DescribeSecret         │            │
│                                    └───────────┬───────────────┘            │
│                                                │                             │
│                                                │ Grants Access               │
│                                                ▼                             │
│                                    ┌───────────────────────────┐            │
│                                    │ AWS Secrets Manager       │            │
│                                    │                           │            │
│                                    │ Secrets:                  │            │
│                                    │ - test-secrets            │            │
│                                    │   {                       │            │
│                                    │     environment: "prod"   │            │
│                                    │     department: "IT"      │            │
│                                    │   }                       │            │
│                                    └───────────────────────────┘            │
└─────────────────────────────────────────────────────────────────────────────┘
                                                ▲
                                                │
                                    5. API Call with Temp Credentials
                                                │
                  ┌─────────────────────────────┴─────────────────┐
                  │                                                │
                  │         4. STS Returns Temp Credentials        │
                  │            AccessKeyId: ASIA...                │
                  │            SecretAccessKey: ...                │
                  │            SessionToken: ...                   │
                  │            Expiration: 1 hour                  │
                  │                                                │
                  └─────────────────────────────┬─────────────────┘
                                                ▲
                                                │
                                    3. AssumeRoleWithWebIdentity
                                       (with JWT token)
                                                │
┌─────────────────────────────────────────────────────────────────────────────┐
│                      EKS Cluster (darey-io-v2-lab-prod)                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  Namespace: external-secrets-system                                │    │
│  │                                                                     │    │
│  │  ┌──────────────────────────┐    ┌─────────────────────────────┐  │    │
│  │  │ ServiceAccount           │    │  Pod                        │  │    │
│  │  │ external-secrets-operator│◄───│  external-secrets-operator  │  │    │
│  │  │                          │    │  -xxx                       │  │    │
│  │  │ Annotations:             │    │                             │  │    │
│  │  │ eks.amazonaws.com/       │    │ Env Vars:                   │  │    │
│  │  │ role-arn=arn:aws:iam::   │    │ AWS_ROLE_ARN=...            │  │    │
│  │  │ 586794457112:role/       │    │ AWS_WEB_IDENTITY_TOKEN_     │  │    │
│  │  │ prod-external-secrets-   │    │ FILE=/var/run/secrets/...   │  │    │
│  │  │ operator-role            │    │                             │  │    │
│  │  │                          │    │ Mounted Token:              │  │    │
│  │  └──────────────────────────┘    │ /var/run/secrets/eks.       │  │    │
│  │                                   │ amazonaws.com/              │  │    │
│  │                                   │ serviceaccount/token        │  │    │
│  │                                   └─────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│                          2. Pod Identity Webhook                             │
│                             Injects JWT Token                                │
│                                      ▲                                       │
│                                      │                                       │
│                          1. Pod starts with ServiceAccount                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Flow Summary:**
1. Pod starts and uses the service account
2. Kubernetes injects JWT token and environment variables
3. AWS SDK calls STS with the JWT token
4. STS validates token and returns temporary credentials
5. Pod uses temp credentials to call AWS Secrets Manager

---

## 🔍 Verification Commands

You can inspect all these components in your running cluster:

### 1. View Service Account Annotation
```bash
kubectl get sa external-secrets-operator -n external-secrets-system -o yaml

# Look for:
# metadata:
#   annotations:
#     eks.amazonaws.com/role-arn: arn:aws:iam::586794457112:role/prod-external-secrets-operator-role
```

### 2. View JWT Token in Pod
```bash
# Get pod name
kubectl get pods -n external-secrets-system

# View the token (it's a long base64-encoded string)
kubectl exec -n external-secrets-system [pod-name] -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# Decode the token to see its contents (paste the token)
echo "[TOKEN]" | cut -d. -f2 | base64 -d | jq .
```

### 3. View Environment Variables
```bash
kubectl exec -n external-secrets-system [pod-name] -- env | grep AWS

# You should see:
# AWS_ROLE_ARN=arn:aws:iam::586794457112:role/prod-external-secrets-operator-role
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

### 4. View OIDC Provider in AWS
```bash
# List OIDC providers
aws iam list-open-id-connect-providers

# Get details of your provider
aws iam get-open-id-connect-provider --open-id-connect-provider-arn [ARN]
```

### 5. View IAM Role Trust Policy
```bash
# View the role
aws iam get-role --role-name prod-external-secrets-operator-role

# View the trust policy (AssumeRolePolicyDocument)
aws iam get-role --role-name prod-external-secrets-operator-role | jq '.Role.AssumeRolePolicyDocument'
```

### 6. View IAM Role Permissions
```bash
# List attached policies
aws iam list-attached-role-policies --role-name prod-external-secrets-operator-role

# Get policy details
aws iam list-role-policies --role-name prod-external-secrets-operator-role

# Get inline policy
aws iam get-role-policy --role-name prod-external-secrets-operator-role --policy-name [policy-name]
```

### 7. View CloudTrail Logs of AssumeRoleWithWebIdentity
```bash
# See who assumed the role (requires CloudTrail enabled)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 10

# Filter for specific role
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  | jq '.Events[] | select(.CloudTrailEvent | contains("prod-external-secrets-operator-role"))'
```

### 8. Verify ClusterSecretStore and ExternalSecret
```bash
# View ClusterSecretStore status
kubectl get clustersecretstore aws-secrets-manager -o yaml

# View ExternalSecret status
kubectl get externalsecret test-secrets -n default -o yaml

# View the created Kubernetes secret
kubectl get secret test-secrets -n default
kubectl describe secret test-secrets -n default
```

---

## 🎯 Why Each Component Matters

### Why OIDC Provider?
Without the OIDC provider registered in IAM, AWS would have no way to verify that the JWT token came from your cluster. The OIDC provider acts as a trust anchor.

### Why Service Account Annotation?
The annotation `eks.amazonaws.com/role-arn` tells the EKS Pod Identity Webhook to inject the JWT token and set environment variables. Without it, pods would have no credentials.

### Why Trust Policy Conditions?
The conditions in the trust policy (`sub` and `aud`) prevent other service accounts or malicious actors from assuming the role. Only the exact service account specified can use this role.

### Why Temporary Credentials?
Temporary credentials that expire after 1 hour minimize the damage if they're somehow leaked. They also automatically rotate without any manual intervention.

### Why ClusterSecretStore vs SecretStore?
We use `ClusterSecretStore` because it can reference a service account in a different namespace (`external-secrets-system`). A namespaced `SecretStore` can't specify a namespace for the service account reference, which caused our initial authentication failure.

---

## 🚨 Common Issues and Troubleshooting

### Issue 1: "AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Symptoms:**
```
WebIdentityErr: failed to retrieve credentials
caused by: AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity
status code: 403
```

**Causes:**
- Service account namespace/name doesn't match the IAM role trust policy
- OIDC provider not properly configured
- Token expired or invalid

**Solution:**
Check that the trust policy's `sub` condition matches:
```
system:serviceaccount:[NAMESPACE]:[SERVICE_ACCOUNT_NAME]
```

### Issue 2: "ServiceAccount not found"

**Symptoms:**
```
unable to create session: ServiceAccount "external-secrets-operator" not found
```

**Causes:**
- SecretStore trying to reference service account in wrong namespace
- Service account doesn't exist

**Solution:**
- Use `ClusterSecretStore` to reference service accounts in other namespaces
- Or create the service account in the same namespace as the SecretStore

### Issue 3: Permissions Denied When Accessing AWS Resources

**Symptoms:**
```
AccessDeniedException: User is not authorized to perform: secretsmanager:GetSecretValue
```

**Causes:**
- IAM role doesn't have required permissions
- IAM policy not attached to role

**Solution:**
Check the IAM policy attached to the role and ensure it has the required permissions.

---

## 📚 Additional Resources

- [AWS EKS IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [External Secrets Operator Authentication](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [OIDC Provider Configuration](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Kubernetes Service Accounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)

---

## 🎓 Key Takeaways

1. **OIDC Provider** = The trust bridge between Kubernetes and AWS IAM
2. **Service Account** = Kubernetes identity (like a user for pods)
3. **IAM Role Trust Policy** = Defines which service accounts can assume the role
4. **JWT Token** = Cryptographic proof of identity, signed by the EKS cluster
5. **AWS STS** = The validator that exchanges tokens for temporary credentials
6. **Temporary Credentials** = Short-lived AWS access keys (typically 1 hour)
7. **IAM Policy** = Defines what permissions the role has (what actions it can perform)

**The beauty of IRSA:** No long-lived credentials to manage, automatic rotation, fine-grained permissions, and a complete audit trail!

---

*Last Updated: October 2024*
*Cluster: darey-io-v2-lab-prod*
*Region: eu-west-2*

