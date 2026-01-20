# GitLab CI/CD Setup Guide

This guide provides step-by-step instructions for configuring the GitLab CI/CD pipeline for your frontend application.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Required GitLab CI/CD Variables](#required-gitlab-cicd-variables)
- [AWS Configuration](#aws-configuration)
- [Project Configuration](#project-configuration)
- [Gradle Configuration](#gradle-configuration)
- [NPM Configuration](#npm-configuration)
- [Deployment Webhooks](#deployment-webhooks)
- [Slack Notifications](#slack-notifications)
- [Verification Steps](#verification-steps)

---

## Prerequisites

Before setting up the pipeline, ensure you have:

1. GitLab project with maintainer or owner permissions
2. AWS Account with ECR repository created
3. AWS IAM user with ECR permissions
4. Slack workspace (optional, for notifications)
5. Deployment webhook endpoints (for dev/staging environments)

---

## Required GitLab CI/CD Variables

Navigate to your GitLab project: **Settings > CI/CD > Variables** and add the following variables:

### AWS Authentication Variables

| Variable Name | Type | Protected | Masked | Description | Example Value |
|--------------|------|-----------|---------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | Variable | Yes | Yes | AWS access key for ECR authentication | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Variable | Yes | Yes | AWS secret access key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_ACCOUNT_ID` | Variable | Yes | No | Your AWS account ID (12 digits) | `123456789012` |
| `AWS_DEFAULT_REGION` | Variable | No | No | AWS region for ECR | `us-east-1` |

### ECR Configuration Variables

| Variable Name | Type | Protected | Masked | Description | Example Value |
|--------------|------|-----------|---------|-------------|---------------|
| `ECR_REPO_NAME` | Variable | No | No | ECR repository name (without registry URL) | `my-frontend-app` |

### Deployment Variables

| Variable Name | Type | Protected | Masked | Description | Example Value |
|--------------|------|-----------|---------|-------------|---------------|
| `DEPLOY_WEBHOOK_DEV` | Variable | Yes | No | Webhook URL for development deployment | `https://deploy.example.com/dev/webhook` |
| `DEPLOY_WEBHOOK_STAGING` | Variable | Yes | No | Webhook URL for staging deployment | `https://deploy.example.com/staging/webhook` |
| `DEPLOY_TOKEN` | Variable | Yes | Yes | Bearer token for deployment webhooks | `your-secure-deploy-token-here` |

### Notification Variables

| Variable Name | Type | Protected | Masked | Description | Example Value |
|--------------|------|-----------|---------|-------------|---------------|
| `SLACK_WEBHOOK_URL` | Variable | No | Yes | Slack incoming webhook URL for failure notifications | `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX` |

---

## AWS Configuration

### Step 1: Create ECR Repository

```bash
# Create ECR repository
aws ecr create-repository \
    --repository-name my-frontend-app \
    --region us-east-1

# Enable image scanning
aws ecr put-image-scanning-configuration \
    --repository-name my-frontend-app \
    --image-scanning-configuration scanOnPush=true \
    --region us-east-1

# Set lifecycle policy (optional - keep last 10 images)
aws ecr put-lifecycle-policy \
    --repository-name my-frontend-app \
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
    }' \
    --region us-east-1
```

### Step 2: Create IAM User for GitLab CI/CD

```bash
# Create IAM user
aws iam create-user --user-name gitlab-ci-ecr-user

# Create access key
aws iam create-access-key --user-name gitlab-ci-ecr-user
```

**Save the Access Key ID and Secret Access Key** - you'll need these for GitLab CI/CD variables.

### Step 3: Attach ECR Policy to IAM User

Create an IAM policy file `ecr-policy.json`:

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
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages"
      ],
      "Resource": "*"
    }
  ]
}
```

Attach the policy:

```bash
# Create the policy
aws iam create-policy \
    --policy-name GitLabCIECRPolicy \
    --policy-document file://ecr-policy.json

# Attach policy to user (replace ACCOUNT_ID)
aws iam attach-user-policy \
    --user-name gitlab-ci-ecr-user \
    --policy-arn arn:aws:iam::ACCOUNT_ID:policy/GitLabCIECRPolicy
```

---

## Project Configuration

### Step 1: Add Required Files to Your Project

Ensure your project has the following files:

#### `build.gradle` (Gradle Build Configuration)

```gradle
plugins {
    id 'java'
    id 'application'
    id 'com.github.spotbugs' version '6.0.0'
}

group = 'com.example'
version = '1.0.0'
sourceCompatibility = '17'

repositories {
    mavenCentral()
}

dependencies {
    // Your project dependencies
    testImplementation 'org.junit.jupiter:junit-jupiter:5.9.3'
    spotbugsPlugins 'com.h3xstream.findsecbugs:findsecbugs-plugin:1.12.0'
}

test {
    useJUnitPlatform()
}

spotbugs {
    toolVersion = '4.8.0'
    effort = 'max'
    reportLevel = 'medium'
}

tasks.named('spotbugsMain') {
    reports {
        html.required = true
        xml.required = true
    }
}
```

#### `package.json` (NPM Configuration)

```json
{
  "name": "frontend-app",
  "version": "1.0.0",
  "scripts": {
    "lint": "eslint src --ext .js,.jsx,.ts,.tsx --max-warnings=0",
    "lint:fix": "eslint src --ext .js,.jsx,.ts,.tsx --fix",
    "test": "jest",
    "build": "webpack --mode production"
  },
  "devDependencies": {
    "eslint": "^8.50.0",
    "@typescript-eslint/eslint-plugin": "^6.7.0",
    "@typescript-eslint/parser": "^6.7.0"
  }
}
```

#### `.eslintrc.json` (ESLint Configuration)

```json
{
  "env": {
    "browser": true,
    "es2021": true,
    "node": true
  },
  "extends": [
    "eslint:recommended"
  ],
  "parserOptions": {
    "ecmaVersion": 2021,
    "sourceType": "module"
  },
  "rules": {
    "no-console": "warn",
    "no-unused-vars": "error",
    "semi": ["error", "always"]
  }
}
```

#### `Dockerfile` (Docker Build Configuration)

```dockerfile
FROM node:18-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## Gradle Configuration

### Gradle Wrapper Setup

If you don't have Gradle wrapper in your project:

```bash
# Initialize Gradle wrapper
gradle wrapper --gradle-version=8.5

# Commit the wrapper files
git add gradlew gradlew.bat gradle/
git commit -m "Add Gradle wrapper"
```

### SpotBugs Configuration

Add SpotBugs plugin to your `build.gradle` (shown in the example above). SpotBugs analyzes Java bytecode for potential bugs.

Key configuration options:
- `effort = 'max'`: Maximum analysis effort
- `reportLevel = 'medium'`: Report medium and high priority issues
- Fails the build if issues are found

---

## NPM Configuration

### ESLint Setup

Install ESLint and required plugins:

```bash
npm install --save-dev eslint \
    @typescript-eslint/eslint-plugin \
    @typescript-eslint/parser
```

Configure ESLint rules based on your project requirements. The pipeline will fail if ESLint finds any issues.

---

## Deployment Webhooks

The pipeline uses webhook-based deployments. Your deployment service should expose endpoints that accept POST requests:

### Expected Webhook Payload

```json
{
  "environment": "development",
  "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:abc1234",
  "commit": "abc1234567890abcdef1234567890abcdef12345",
  "branch": "main",
  "author": "John Doe"
}
```

### Webhook Authentication

The pipeline sends a Bearer token in the Authorization header:

```
Authorization: Bearer your-secure-deploy-token-here
```

Ensure your deployment service validates this token.

### Example Webhook Implementation (Node.js/Express)

```javascript
app.post('/deploy/:env', authenticate, async (req, res) => {
  const { environment, image, commit, branch, author } = req.body;

  // Trigger deployment
  await deployService.deploy({
    environment,
    image,
    commit,
    metadata: { branch, author }
  });

  res.json({ status: 'success', deployment_id: 'xyz123' });
});
```

---

## Slack Notifications

### Step 1: Create Slack Incoming Webhook

1. Go to https://api.slack.com/apps
2. Create a new app or select existing
3. Enable "Incoming Webhooks"
4. Create a new webhook for your desired channel
5. Copy the webhook URL

### Step 2: Add Webhook URL to GitLab

Add the `SLACK_WEBHOOK_URL` variable in GitLab CI/CD settings (see variables table above).

### Notification Behavior

- Notifications are sent **only on pipeline failure**
- Includes project name, branch, commit SHA, and author
- Provides direct link to failed pipeline

### Testing Slack Notification

```bash
curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Test notification from GitLab CI/CD"
  }'
```

---

## Verification Steps

### Step 1: Verify Variable Configuration

Navigate to **Settings > CI/CD > Variables** and verify all required variables are set.

### Step 2: Verify AWS Access

Test AWS credentials locally:

```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=us-east-1

# Test ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Test ECR permissions
aws ecr describe-repositories --region us-east-1
```

### Step 3: Validate Pipeline Configuration

Validate the `.gitlab-ci.yml` syntax:

```bash
# Install GitLab CI Lint tool (requires GitLab CLI)
glab ci lint
```

Or use the GitLab web UI:
1. Go to **CI/CD > Editor**
2. Paste your `.gitlab-ci.yml` content
3. Click "Validate"

### Step 4: Run Test Pipeline

1. Commit and push your changes
2. Navigate to **CI/CD > Pipelines**
3. Monitor the pipeline execution
4. Check each stage:
   - Build: Gradle build completes successfully
   - Test: Unit tests and linting pass
   - Security: Docker image scans pass
   - Deploy: Webhooks triggered successfully

### Step 5: Verify ECR Images

After successful pipeline:

```bash
# List images in ECR
aws ecr list-images \
    --repository-name my-frontend-app \
    --region us-east-1

# Describe specific image
aws ecr describe-images \
    --repository-name my-frontend-app \
    --image-ids imageTag=abc1234 \
    --region us-east-1
```

---

## Pipeline Stages Overview

### Stage 1: Build
- Uses Gradle 8.5 with JDK 17
- Implements aggressive dependency caching (.gradle/caches)
- Builds with `--build-cache` and `--parallel` flags
- Produces artifacts in `build/` directory

### Stage 2: Test
- **Unit Tests**: Runs with Gradle test task
- **ESLint**: Static analysis for JavaScript/TypeScript
- **SpotBugs**: Static analysis for Java code
- All checks must pass (allow_failure: false)

### Stage 3: Security
- **Docker Build**: Creates image tagged with commit SHA
- **GitLab Container Scanning**: Uses Trivy for vulnerability scanning
- **Anchore Scan**: Additional security scanning with Grype
- **Push to ECR**: Images pushed only after scans pass

### Stage 4: Deploy
- **Development**: Auto-deploys on develop/main branches
- **Staging**: Manual deployment via webhook
- Uses GitLab Environments for tracking

### Stage 5: Notification
- Slack notification on pipeline failure
- Includes full pipeline context

---

## Troubleshooting

### Issue: AWS ECR Authentication Failed

**Solution:**
```bash
# Verify credentials
aws sts get-caller-identity

# Check ECR permissions
aws ecr get-authorization-token --region us-east-1
```

### Issue: Gradle Build Fails

**Solution:**
- Check Gradle wrapper is committed: `gradlew`, `gradlew.bat`, `gradle/wrapper/`
- Verify Java version compatibility (requires JDK 17)
- Clear Gradle cache: Settings > CI/CD > Clear Runner Caches

### Issue: ESLint or SpotBugs Failing

**Solution:**
- Run locally to see specific issues:
  ```bash
  npm run lint
  gradle spotbugsMain
  ```
- Fix reported issues or adjust rule severity

### Issue: Container Scanning Fails

**Solution:**
- Review vulnerability report in job artifacts
- Update base image versions in Dockerfile
- If false positives, consider adjusting severity threshold

### Issue: Deployment Webhook Fails

**Solution:**
- Verify webhook URL is correct
- Check bearer token is valid
- Test webhook manually with curl
- Review deployment service logs

---

## Security Best Practices

1. **Always use Masked variables** for secrets (AWS keys, tokens)
2. **Protect production variables** to restrict access to protected branches
3. **Rotate credentials regularly** (AWS keys, deploy tokens)
4. **Review security scan reports** before pushing to production
5. **Use specific image tags** (commit SHA) instead of 'latest' in production
6. **Enable ECR image scanning** for additional security
7. **Limit IAM permissions** to minimum required access

---

## Additional Resources

- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [Gradle Build Cache](https://docs.gradle.org/current/userguide/build_cache.html)
- [Trivy Security Scanner](https://github.com/aquasecurity/trivy)
- [Anchore Grype](https://github.com/anchore/grype)
- [SpotBugs](https://spotbugs.github.io/)

---

## Support

For issues or questions:
1. Check pipeline job logs in GitLab
2. Review this setup guide
3. Consult your DevOps team
4. Open an issue in your project repository

---

**Last Updated:** 2026-01-20
**Pipeline Version:** 1.0.0
