# CI/CD Pipeline Setup Guide

This guide provides step-by-step instructions to configure the GitLab CI/CD pipeline for your Go application.

## Prerequisites

1. GitLab account with CI/CD enabled
2. AWS account with ECR repository created
3. AWS ECS clusters and services configured for QA and UAT environments
4. Slack workspace (for failure notifications)

---

## Required GitLab CI/CD Variables

Configure these variables in **GitLab** → **Settings** → **CI/CD** → **Variables**

### AWS Configuration

| Variable Name | Type | Protected | Masked | Description | Example Value |
|--------------|------|-----------|--------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | Variable | ✅ Yes | ✅ Yes | AWS Access Key for ECR/ECS access | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Variable | ✅ Yes | ✅ Yes | AWS Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | Variable | ❌ No | ❌ No | AWS Region for ECR/ECS | `us-east-1` |
| `AWS_ECR_REGISTRY` | Variable | ❌ No | ❌ No | ECR Registry URL | `123456789012.dkr.ecr.us-east-1.amazonaws.com` |
| `AWS_ECR_REPOSITORY` | Variable | ❌ No | ❌ No | ECR Repository name | `my-go-app` |

### ECS Deployment Configuration

| Variable Name | Type | Protected | Masked | Description | Example Value |
|--------------|------|-----------|--------|-------------|---------------|
| `ECS_CLUSTER_QA` | Variable | ❌ No | ❌ No | ECS Cluster name for QA | `my-app-qa-cluster` |
| `ECS_SERVICE_QA` | Variable | ❌ No | ❌ No | ECS Service name for QA | `my-app-qa-service` |
| `ECS_CLUSTER_UAT` | Variable | ❌ No | ❌ No | ECS Cluster name for UAT | `my-app-uat-cluster` |
| `ECS_SERVICE_UAT` | Variable | ❌ No | ❌ No | ECS Service name for UAT | `my-app-uat-service` |

### Notification Configuration

| Variable Name | Type | Protected | Masked | Description | Example Value |
|--------------|------|-----------|--------|-------------|---------------|
| `SLACK_WEBHOOK_URL` | Variable | ✅ Yes | ✅ Yes | Slack Incoming Webhook URL for failure notifications | `https://hooks.slack.com/services/T00/B00/XXX` |

---

## Step-by-Step Setup

### 1. AWS ECR Setup

Create an ECR repository for your Docker images:

```bash
aws ecr create-repository \
  --repository-name my-go-app \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true
```

Note the `repositoryUri` from the output - this becomes your `AWS_ECR_REGISTRY` + `AWS_ECR_REPOSITORY`.

### 2. AWS IAM Configuration

Create an IAM user with the following permissions:

**Required IAM Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": [
        "arn:aws:ecs:us-east-1:123456789012:service/my-app-qa-cluster/*",
        "arn:aws:ecs:us-east-1:123456789012:service/my-app-uat-cluster/*"
      ]
    }
  ]
}
```

Generate access keys for this IAM user and use them for `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

### 3. Slack Webhook Setup

1. Go to your Slack workspace → **Apps** → **Incoming Webhooks**
2. Click **Add to Slack**
3. Choose the channel for notifications (e.g., `#deployments` or `#ci-alerts`)
4. Copy the Webhook URL
5. Add it to GitLab as `SLACK_WEBHOOK_URL`

### 4. GitLab CI/CD Variables Configuration

1. Navigate to your GitLab project
2. Go to **Settings** → **CI/CD** → **Variables**
3. Click **Add Variable** for each variable listed above
4. For sensitive values (credentials, tokens), enable:
   - **Protect variable** - Only available in protected branches
   - **Mask variable** - Hide value in job logs

**Quick Add Script:**
```bash
# Using GitLab CLI (glab)
glab variable set AWS_ACCESS_KEY_ID "AKIAIOSFODNN7EXAMPLE" --masked --protected
glab variable set AWS_SECRET_ACCESS_KEY "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" --masked --protected
glab variable set AWS_REGION "us-east-1"
glab variable set AWS_ECR_REGISTRY "123456789012.dkr.ecr.us-east-1.amazonaws.com"
glab variable set AWS_ECR_REPOSITORY "my-go-app"
glab variable set ECS_CLUSTER_QA "my-app-qa-cluster"
glab variable set ECS_SERVICE_QA "my-app-qa-service"
glab variable set ECS_CLUSTER_UAT "my-app-uat-cluster"
glab variable set ECS_SERVICE_UAT "my-app-uat-service"
glab variable set SLACK_WEBHOOK_URL "https://hooks.slack.com/services/T00/B00/XXX" --masked --protected
```

### 5. Project Configuration

Ensure your Go project has the following structure:

```
project-root/
├── .gitlab-ci.yml          # Pipeline configuration (created)
├── Dockerfile              # Docker image definition (required)
├── go.mod                  # Go module file (required)
├── go.sum                  # Go dependencies checksum (required)
├── cmd/
│   └── app/
│       └── main.go         # Application entry point
└── ...
```

**Sample Dockerfile** (create if not exists):
```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main ./cmd/app

# Runtime stage
FROM alpine:3.19

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy binary from builder
COPY --from=builder /app/main .

EXPOSE 8080

CMD ["./main"]
```

### 6. Enable GitLab CI/CD

1. Commit and push `.gitlab-ci.yml` to your repository
2. Navigate to **CI/CD** → **Pipelines** in GitLab
3. The pipeline should trigger automatically on push

---

## Pipeline Behavior

### Branch-Based Deployments

| Branch | Build | Test | Security | Package | QA Deploy | UAT Deploy |
|--------|-------|------|----------|---------|-----------|------------|
| `develop` | ✅ | ✅ | ✅ | ✅ | ✅ Auto | ❌ |
| `main` | ✅ | ✅ | ✅ | ✅ | ✅ Auto | ✅ Manual |
| Feature branches | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |

### Manual Deployment Triggers

UAT deployments require manual approval:
1. Go to **CI/CD** → **Pipelines**
2. Click on the pipeline for the `main` branch
3. Click the **Play** button (▶️) next to `deploy:uat`

---

## Verification

### Test the Pipeline

1. **Create a test commit:**
   ```bash
   git checkout -b test-pipeline
   echo "// Test" >> cmd/app/main.go
   git add .
   git commit -m "test: verify CI/CD pipeline"
   git push origin test-pipeline
   ```

2. **Check pipeline execution:**
   - Go to **CI/CD** → **Pipelines**
   - Click on the latest pipeline
   - Verify all stages pass

3. **Verify ECR image:**
   ```bash
   aws ecr describe-images \
     --repository-name my-go-app \
     --region us-east-1
   ```

### Verify Slack Notifications

To test failure notifications:
1. Temporarily break a test
2. Push to trigger pipeline
3. Check your Slack channel for failure alert

---

## Troubleshooting

### Common Issues

**Issue: "Unable to locate credentials"**
- **Solution:** Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set correctly
- Check IAM user has proper permissions

**Issue: "denied: access forbidden"**
- **Solution:** Ensure IAM policy includes `ecr:GetAuthorizationToken`
- Verify ECR repository exists and name matches `AWS_ECR_REPOSITORY`

**Issue: "golangci-lint: command not found"**
- **Solution:** The pipeline uses a pre-built `golangci-lint` image - no action needed
- If using custom image, install: `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest`

**Issue: "dependency-check failed"**
- **Solution:** Review the `dependency-check-report/` artifact
- Update vulnerable dependencies or add suppressions if false positives

**Issue: Pipeline hangs on ECS deployment**
- **Solution:** Check ECS service configuration
- Verify task definition uses correct image tag
- Check CloudWatch logs for container startup issues

**Issue: Slack notification not received**
- **Solution:** Verify `SLACK_WEBHOOK_URL` is correct
- Test webhook manually:
  ```bash
  curl -X POST $SLACK_WEBHOOK_URL \
    -H 'Content-Type: application/json' \
    -d '{"text":"Test message"}'
  ```

### Debug Mode

Enable debug logging for specific jobs:

```yaml
job_name:
  variables:
    CI_DEBUG_TRACE: "true"
  script:
    - ...
```

---

## Security Best Practices

1. **Rotate AWS credentials** regularly (every 90 days)
2. **Use protected variables** for all sensitive data
3. **Enable branch protection** on `main` and `develop`
4. **Review OWASP reports** regularly in pipeline artifacts
5. **Keep dependencies updated** to avoid security vulnerabilities
6. **Use least-privilege IAM policies** - only grant necessary permissions

---

## Cost Optimization

1. **Cache is key:** The aggressive caching strategy reduces build times by ~70%
2. **Clean old ECR images:** Set up lifecycle policies
   ```bash
   aws ecr put-lifecycle-policy \
     --repository-name my-go-app \
     --lifecycle-policy-text '{
       "rules": [{
         "rulePriority": 1,
         "description": "Keep last 10 images",
         "selection": {
           "tagStatus": "any",
           "countType": "imageCountMoreThan",
           "countNumber": 10
         },
         "action": { "type": "expire" }
       }]
     }'
   ```
3. **Use spot runners:** Configure GitLab runners on AWS Spot instances

---

## Next Steps

After successful setup:

1. ✅ Customize coverage thresholds in `test:unit` job
2. ✅ Add integration tests if needed
3. ✅ Configure environment-specific variables in GitLab Environments
4. ✅ Set up monitoring and alerting for deployed services
5. ✅ Document rollback procedures for production incidents

---

## Support

For issues or questions:
- **GitLab CI/CD Docs:** https://docs.gitlab.com/ee/ci/
- **AWS ECR Docs:** https://docs.aws.amazon.com/ecr/
- **OWASP Dependency-Check:** https://jeremylong.github.io/DependencyCheck/

---

**Pipeline Status Badge:**

Add to your README.md:
```markdown
[![Pipeline Status](https://gitlab.com/your-namespace/your-project/badges/main/pipeline.svg)](https://gitlab.com/your-namespace/your-project/-/pipelines)
```
