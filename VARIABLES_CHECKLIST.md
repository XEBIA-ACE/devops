# GitLab CI/CD Variables Checklist

Use this checklist to ensure all required variables are configured correctly.

## Configuration Path
**GitLab → Your Project → Settings → CI/CD → Variables → Add Variable**

---

## ✅ Required Variables

### 1. AWS Credentials

- [ ] **AWS_ACCESS_KEY_ID**
  - Value: `AKIA...` (20 characters)
  - ☑️ Masked
  - ☑️ Protected
  - Description: AWS Access Key with ECR/ECS permissions

- [ ] **AWS_SECRET_ACCESS_KEY**
  - Value: `wJalr...` (40 characters)
  - ☑️ Masked
  - ☑️ Protected
  - Description: AWS Secret Access Key

- [ ] **AWS_REGION**
  - Value: `us-east-1` (or your region)
  - ☐ Masked
  - ☐ Protected
  - Description: AWS region for all services

### 2. AWS ECR Configuration

- [ ] **AWS_ECR_REGISTRY**
  - Value: `123456789012.dkr.ecr.us-east-1.amazonaws.com`
  - ☐ Masked
  - ☐ Protected
  - Description: Full ECR registry URL (without repository name)

- [ ] **AWS_ECR_REPOSITORY**
  - Value: `my-go-app` (your repo name)
  - ☐ Masked
  - ☐ Protected
  - Description: ECR repository name only

### 3. ECS QA Environment

- [ ] **ECS_CLUSTER_QA**
  - Value: `my-app-qa-cluster`
  - ☐ Masked
  - ☐ Protected
  - Description: ECS cluster name for QA environment

- [ ] **ECS_SERVICE_QA**
  - Value: `my-app-qa-service`
  - ☐ Masked
  - ☐ Protected
  - Description: ECS service name for QA environment

### 4. ECS UAT Environment

- [ ] **ECS_CLUSTER_UAT**
  - Value: `my-app-uat-cluster`
  - ☐ Masked
  - ☐ Protected
  - Description: ECS cluster name for UAT environment

- [ ] **ECS_SERVICE_UAT**
  - Value: `my-app-uat-service`
  - ☐ Masked
  - ☐ Protected
  - Description: ECS service name for UAT environment

### 5. Notifications

- [ ] **SLACK_WEBHOOK_URL**
  - Value: `https://hooks.slack.com/services/T.../B.../...`
  - ☑️ Masked
  - ☑️ Protected
  - Description: Slack incoming webhook for failure alerts

---

## 📋 Quick Validation Commands

After adding variables, verify they're set correctly:

### Check AWS Credentials
```bash
# Test AWS CLI access
aws sts get-caller-identity --region $AWS_REGION

# Expected output: Account ID and user ARN
```

### Check ECR Repository
```bash
# Verify ECR repository exists
aws ecr describe-repositories \
  --repository-names $AWS_ECR_REPOSITORY \
  --region $AWS_REGION

# Expected output: Repository details with repositoryUri
```

### Check ECS Clusters
```bash
# Verify QA cluster
aws ecs describe-clusters \
  --clusters $ECS_CLUSTER_QA \
  --region $AWS_REGION

# Verify UAT cluster
aws ecs describe-clusters \
  --clusters $ECS_CLUSTER_UAT \
  --region $AWS_REGION

# Expected output: Cluster status should be "ACTIVE"
```

### Check ECS Services
```bash
# Verify QA service
aws ecs describe-services \
  --cluster $ECS_CLUSTER_QA \
  --services $ECS_SERVICE_QA \
  --region $AWS_REGION

# Verify UAT service
aws ecs describe-services \
  --cluster $ECS_CLUSTER_UAT \
  --services $ECS_SERVICE_UAT \
  --region $AWS_REGION

# Expected output: Service status should be "ACTIVE"
```

### Test Slack Webhook
```bash
# Send test notification
curl -X POST $SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"✅ CI/CD Setup Test - Webhook is working!"}'

# Expected result: Message appears in configured Slack channel
```

---

## 🔒 Security Best Practices

### Variable Protection Settings

| Setting | When to Enable | Variables |
|---------|---------------|-----------|
| **Masked** | Always for secrets | Credentials, tokens, webhook URLs |
| **Protected** | For production secrets | AWS credentials, Slack webhook |
| **Expand** | Rarely needed | Only if referencing other variables |

### Protection Guidelines

✅ **DO:**
- Enable "Masked" for ALL credentials and sensitive data
- Enable "Protected" for production/sensitive environment variables
- Use least-privilege IAM policies for AWS credentials
- Rotate AWS credentials every 90 days
- Limit variable access to specific environments when possible

❌ **DON'T:**
- Store secrets in code or commit history
- Use the same AWS credentials for dev and prod
- Share webhook URLs in public channels
- Disable masking for credentials "for debugging"
- Use root AWS account credentials

---

## 🧪 Test Your Setup

### Step 1: Add Variables to GitLab

Use the GitLab CLI (faster method):

```bash
# Install glab if not already installed
# brew install glab  # macOS
# sudo snap install glab  # Linux

# Authenticate
glab auth login

# Add all variables (update values!)
glab variable set AWS_ACCESS_KEY_ID "AKIAIOSFODNN7EXAMPLE" --masked --protected
glab variable set AWS_SECRET_ACCESS_KEY "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" --masked --protected
glab variable set AWS_REGION "us-east-1"
glab variable set AWS_ECR_REGISTRY "123456789012.dkr.ecr.us-east-1.amazonaws.com"
glab variable set AWS_ECR_REPOSITORY "my-go-app"
glab variable set ECS_CLUSTER_QA "my-app-qa-cluster"
glab variable set ECS_SERVICE_QA "my-app-qa-service"
glab variable set ECS_CLUSTER_UAT "my-app-uat-cluster"
glab variable set ECS_SERVICE_UAT "my-app-uat-service"
glab variable set SLACK_WEBHOOK_URL "https://hooks.slack.com/services/XXX" --masked --protected
```

### Step 2: Verify Variables Are Set

```bash
# List all CI/CD variables (values will be masked)
glab variable list

# Expected output: Table with all 10 variables
```

### Step 3: Trigger Test Pipeline

```bash
# Create test commit
git checkout -b test-cicd-setup
echo "# CI/CD Test" >> README.md
git add README.md
git commit -m "test: verify CI/CD variable configuration"
git push origin test-cicd-setup

# Watch pipeline
glab pipeline ci view
```

### Step 4: Check Pipeline Logs

1. Go to **CI/CD → Pipelines**
2. Click on the running pipeline
3. Check each job for errors related to missing variables:
   - ❌ "Unable to locate credentials" → Check AWS variables
   - ❌ "repository does not exist" → Check ECR variables
   - ❌ "cluster not found" → Check ECS variables
   - ❌ "webhook failed" → Check Slack webhook

---

## 🆘 Troubleshooting

### Variable Not Available in Job

**Symptom:** Job fails with "variable not set"

**Solutions:**
1. Check variable name matches exactly (case-sensitive)
2. Verify variable is not limited to specific environments
3. If protected, ensure branch is protected in GitLab settings
4. Check job `only:` rules don't exclude the branch

### Masked Variable Shows `[masked]` in Logs

**This is expected behavior!** Masked variables are hidden in logs for security.

To debug without exposing secrets:
```yaml
script:
  - echo "AWS_REGION is set: ${AWS_REGION}"  # Shows value (not sensitive)
  - echo "AWS_ACCESS_KEY_ID is set: ${AWS_ACCESS_KEY_ID:0:4}..."  # Shows first 4 chars
```

### AWS Authentication Fails

**Symptom:** "Unable to locate credentials" or "Access Denied"

**Solutions:**
1. Verify IAM user has required permissions (see SETUP_GUIDE.md)
2. Check credentials are not expired
3. Test credentials locally:
   ```bash
   export AWS_ACCESS_KEY_ID="your-key"
   export AWS_SECRET_ACCESS_KEY="your-secret"
   aws sts get-caller-identity
   ```
4. Verify no extra whitespace in variable values

---

## 📊 Variables Summary Table

| Variable | Type | Protected | Masked | Required For |
|----------|------|-----------|--------|--------------|
| AWS_ACCESS_KEY_ID | Secret | ✅ | ✅ | ECR push, ECS deploy |
| AWS_SECRET_ACCESS_KEY | Secret | ✅ | ✅ | ECR push, ECS deploy |
| AWS_REGION | Config | ❌ | ❌ | All AWS operations |
| AWS_ECR_REGISTRY | Config | ❌ | ❌ | Docker push |
| AWS_ECR_REPOSITORY | Config | ❌ | ❌ | Docker push |
| ECS_CLUSTER_QA | Config | ❌ | ❌ | QA deployment |
| ECS_SERVICE_QA | Config | ❌ | ❌ | QA deployment |
| ECS_CLUSTER_UAT | Config | ❌ | ❌ | UAT deployment |
| ECS_SERVICE_UAT | Config | ❌ | ❌ | UAT deployment |
| SLACK_WEBHOOK_URL | Secret | ✅ | ✅ | Failure notifications |

**Total: 10 required variables**

---

## ✅ Final Checklist

Before triggering your first real pipeline:

- [ ] All 10 variables are added to GitLab
- [ ] AWS credentials are masked and protected
- [ ] Slack webhook is masked and protected
- [ ] ECR repository exists and is accessible
- [ ] ECS clusters and services are running
- [ ] Test pipeline runs successfully
- [ ] Slack notification received on test failure
- [ ] Environment URLs are updated in `.gitlab-ci.yml`
- [ ] Dockerfile exists in project root
- [ ] `go.mod` and `go.sum` exist

**Ready to deploy!** 🚀

---

## 📚 Additional Resources

- [GitLab CI/CD Variables Docs](https://docs.gitlab.com/ee/ci/variables/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks)
