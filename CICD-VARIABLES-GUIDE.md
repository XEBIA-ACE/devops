# GitLab CI/CD Variables Configuration Guide

## Overview

This guide provides comprehensive instructions for configuring all required CI/CD variables in GitLab for your Node.js Express API pipeline.

---

## Table of Contents

1. [How to Add CI/CD Variables in GitLab](#how-to-add-cicd-variables-in-gitlab)
2. [Required Variables](#required-variables)
3. [Optional Variables](#optional-variables)
4. [Security Best Practices](#security-best-practices)
5. [Variable Groups by Stage](#variable-groups-by-stage)
6. [Troubleshooting](#troubleshooting)

---

## How to Add CI/CD Variables in GitLab

### Method 1: Project-Level Variables (Recommended)

1. Navigate to your GitLab project
2. Go to **Settings** → **CI/CD**
3. Expand the **Variables** section
4. Click **Add variable**
5. Configure the variable:
   - **Key**: Variable name (e.g., `SNYK_TOKEN`)
   - **Value**: The actual value
   - **Type**: Variable (default) or File
   - **Environment scope**: All (default) or specific environment
   - **Protect variable**: ✓ (for production secrets)
   - **Mask variable**: ✓ (for sensitive values)
6. Click **Add variable**

### Method 2: Group-Level Variables (For Multiple Projects)

1. Navigate to your GitLab group
2. Go to **Settings** → **CI/CD**
3. Follow steps 3-6 above

### Method 3: Instance-Level Variables (Admin Only)

1. Navigate to **Admin Area**
2. Go to **Settings** → **CI/CD**
3. Expand **Variables**
4. Follow similar steps

---

## Required Variables

### 🔐 1. GitLab Container Registry (Built-in Variables)

These are automatically provided by GitLab:

| Variable | Description | Auto-provided |
|----------|-------------|---------------|
| `CI_REGISTRY` | GitLab Container Registry URL | ✅ |
| `CI_REGISTRY_USER` | Registry username | ✅ |
| `CI_REGISTRY_PASSWORD` | Registry password | ✅ |
| `CI_REGISTRY_IMAGE` | Full image path | ✅ |

**No action required** - These are available by default.

---

### ☁️ 2. Google Cloud Platform (GCP) / GKE Variables

#### `GCP_SERVICE_ACCOUNT_KEY`
- **Type**: Variable
- **Protected**: ✅
- **Masked**: ✅
- **Description**: Base64-encoded GCP service account JSON key
- **How to get**:
  ```bash
  # Create service account in GCP
  gcloud iam service-accounts create gitlab-ci-deployer \
    --display-name="GitLab CI/CD Deployer"

  # Grant necessary roles
  gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:gitlab-ci-deployer@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/container.developer"

  # Create and download key
  gcloud iam service-accounts keys create key.json \
    --iam-account=gitlab-ci-deployer@PROJECT_ID.iam.gserviceaccount.com

  # Base64 encode the key
  cat key.json | base64 -w 0 > key-base64.txt

  # Use the content of key-base64.txt as the variable value
  ```

#### `GCP_PROJECT_ID`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ❌
- **Value**: Your GCP project ID (e.g., `my-project-123456`)
- **Example**: `express-api-prod`

#### `GKE_CLUSTER`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ❌
- **Value**: Your GKE cluster name
- **Example**: `production-cluster`

#### `GKE_ZONE`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ❌
- **Value**: GCP zone where your GKE cluster is located
- **Example**: `us-central1-a`

---

### 🔍 3. SonarCloud Variables

#### `SONAR_TOKEN`
- **Type**: Variable
- **Protected**: ✅
- **Masked**: ✅
- **Description**: SonarCloud authentication token
- **How to get**:
  1. Go to https://sonarcloud.io
  2. Login with your account
  3. Click on your avatar → **My Account**
  4. Go to **Security** tab
  5. Generate new token
  6. Copy and add to GitLab

#### `SONAR_PROJECT_KEY`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ❌
- **Value**: Your SonarCloud project key
- **Example**: `my-org_express-api`
- **How to get**: From your SonarCloud project settings

#### `SONAR_ORGANIZATION`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ❌
- **Value**: Your SonarCloud organization key
- **Example**: `my-organization`

---

### 🛡️ 4. Snyk Security Variables

#### `SNYK_TOKEN`
- **Type**: Variable
- **Protected**: ✅
- **Masked**: ✅
- **Description**: Snyk API authentication token
- **How to get**:
  1. Go to https://snyk.io
  2. Login with your account
  3. Go to **Account Settings**
  4. Click **API Token** section
  5. Click **Generate** or copy existing token
  6. Add to GitLab

#### `SNYK_ORG_ID`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ❌
- **Value**: Your Snyk organization ID
- **Example**: `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
- **How to get**: From Snyk organization settings URL

---

### 🗄️ 5. Database Variables

#### Staging Environment

#### `DATABASE_URL`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ✅
- **Environment**: `staging`
- **Value**: PostgreSQL connection string for staging
- **Example**: `postgresql://user:password@staging-db.example.com:5432/appdb`

#### Production Environment

#### `DATABASE_URL_PROD`
- **Type**: Variable
- **Protected**: ✅
- **Masked**: ✅
- **Environment**: `production`
- **Value**: PostgreSQL connection string for production
- **Example**: `postgresql://user:password@prod-db.example.com:5432/appdb`

---

### 📦 6. Redis Cache Variables

#### Staging Environment

#### `REDIS_URL`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ✅
- **Environment**: `staging`
- **Value**: Redis connection string for staging
- **Example**: `redis://user:password@staging-redis.example.com:6379`

#### Production Environment

#### `REDIS_URL_PROD`
- **Type**: Variable
- **Protected**: ✅
- **Masked**: ✅
- **Environment**: `production`
- **Value**: Redis connection string for production
- **Example**: `redis://user:password@prod-redis.example.com:6379`

---

### 🔑 7. Application Secrets

#### Staging Environment

#### `JWT_SECRET`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ✅
- **Environment**: `staging`
- **Value**: JWT signing secret for staging
- **Example**: Generate with `openssl rand -hex 32`

#### `API_KEY`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ✅
- **Environment**: `staging`
- **Value**: API key for external services (staging)

#### Production Environment

#### `JWT_SECRET_PROD`
- **Type**: Variable
- **Protected**: ✅
- **Masked**: ✅
- **Environment**: `production`
- **Value**: JWT signing secret for production
- **Example**: Generate with `openssl rand -hex 64`

#### `API_KEY_PROD`
- **Type**: Variable
- **Protected**: ✅
- **Masked**: ✅
- **Environment**: `production`
- **Value**: API key for external services (production)

---

### 📧 8. Notification Variables (Optional but Recommended)

#### `SLACK_WEBHOOK_URL`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ✅
- **Value**: Slack incoming webhook URL
- **Example**: `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX`
- **How to get**:
  1. Go to https://api.slack.com/apps
  2. Create or select your app
  3. Enable **Incoming Webhooks**
  4. Add webhook to workspace
  5. Copy webhook URL

#### `TEAMS_WEBHOOK_URL`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ✅
- **Value**: Microsoft Teams incoming webhook URL
- **Example**: `https://outlook.office.com/webhook/...`
- **How to get**:
  1. Go to your Teams channel
  2. Click **...** → **Connectors**
  3. Configure **Incoming Webhook**
  4. Copy webhook URL

#### `GITLAB_USER_EMAIL`
- **Type**: Variable
- **Protected**: ❌
- **Masked**: ❌
- **Value**: Email for GitLab notifications
- **Example**: `devops@company.com`

---

## Optional Variables

### Performance & Optimization

#### `NPM_CONFIG_CACHE`
- **Default**: `$CI_PROJECT_DIR/.npm`
- **Override**: Not usually necessary

#### `NODE_ENV`
- **Default**: `production`
- **Override**: Only if you need different behavior

---

## Security Best Practices

### ✅ Do's

1. **Always protect production variables**
   - Check "Protect variable" for all production secrets
   - This ensures they're only available on protected branches

2. **Always mask sensitive values**
   - Check "Mask variable" for tokens, passwords, keys
   - Prevents values from appearing in job logs

3. **Use environment-specific variables**
   - Suffix production variables with `_PROD`
   - Use environment scopes when possible

4. **Rotate secrets regularly**
   - Change tokens and passwords every 90 days
   - Update immediately if compromised

5. **Use strong secrets**
   - Generate random secrets with sufficient entropy
   - Example: `openssl rand -hex 32`

6. **Audit access regularly**
   - Review who has access to CI/CD variables
   - Remove access for former team members

### ❌ Don'ts

1. **Never hardcode secrets** in `.gitlab-ci.yml`
2. **Never commit secrets** to your repository
3. **Never share secrets** via insecure channels (email, chat)
4. **Never use the same secrets** across environments
5. **Never disable masking** for sensitive values

---

## Variable Groups by Stage

### Build Stage
- `NPM_CONFIG_CACHE` (auto-configured)
- `NODE_ENV` (auto-configured)

### Test Stage
- `POSTGRES_DB` (auto-configured per job)
- `POSTGRES_USER` (auto-configured per job)
- `POSTGRES_PASSWORD` (auto-configured per job)
- `REDIS_HOST` (auto-configured per job)

### Static Analysis Stage
- `SONAR_TOKEN` ⚠️ **Required**
- `SONAR_PROJECT_KEY` ⚠️ **Required**
- `SONAR_ORGANIZATION` ⚠️ **Required**

### Security Stage
- `SNYK_TOKEN` ⚠️ **Required**
- `SNYK_ORG_ID` ⚠️ **Required**

### Package Stage
- `CI_REGISTRY` (auto-provided)
- `CI_REGISTRY_USER` (auto-provided)
- `CI_REGISTRY_PASSWORD` (auto-provided)

### Deploy Stage
- `GCP_SERVICE_ACCOUNT_KEY` ⚠️ **Required**
- `GCP_PROJECT_ID` ⚠️ **Required**
- `GKE_CLUSTER` ⚠️ **Required**
- `GKE_ZONE` ⚠️ **Required**
- `DATABASE_URL` / `DATABASE_URL_PROD` ⚠️ **Required**
- `REDIS_URL` / `REDIS_URL_PROD` ⚠️ **Required**
- `JWT_SECRET` / `JWT_SECRET_PROD` ⚠️ **Required**
- `API_KEY` / `API_KEY_PROD` ⚠️ **Required**

### Notification Stage
- `SLACK_WEBHOOK_URL` (optional)
- `TEAMS_WEBHOOK_URL` (optional)
- `GITLAB_USER_EMAIL` (optional)

---

## Troubleshooting

### Issue: "Variable not found" error

**Solution**: Ensure the variable is:
- Added at the correct level (project/group/instance)
- Not restricted to a specific environment scope
- Available for the branch being built

### Issue: "Authentication failed" for GCP

**Solution**:
- Verify the service account key is correctly base64-encoded
- Ensure service account has necessary permissions
- Check that the key hasn't expired

### Issue: "Container registry authentication failed"

**Solution**:
- Verify Container Registry is enabled for your project
- Check that `CI_REGISTRY_*` variables are available
- Ensure GitLab Runner has internet access

### Issue: Masked variable showing in logs

**Solution**:
- Variable value must be at least 8 characters
- Variable must not contain special characters that prevent masking
- Re-create the variable with "Mask variable" enabled

### Issue: SonarCloud/Snyk failing silently

**Solution**:
- Check token validity by testing it manually
- Verify organization/project keys are correct
- Ensure `allow_failure: true` isn't hiding real errors

---

## Quick Setup Checklist

Use this checklist to ensure all required variables are configured:

### ☁️ GCP/GKE Configuration
- [ ] `GCP_SERVICE_ACCOUNT_KEY` (base64-encoded)
- [ ] `GCP_PROJECT_ID`
- [ ] `GKE_CLUSTER`
- [ ] `GKE_ZONE`

### 🔍 Code Quality & Security
- [ ] `SONAR_TOKEN`
- [ ] `SONAR_PROJECT_KEY`
- [ ] `SONAR_ORGANIZATION`
- [ ] `SNYK_TOKEN`
- [ ] `SNYK_ORG_ID`

### 🗄️ Application Secrets - Staging
- [ ] `DATABASE_URL`
- [ ] `REDIS_URL`
- [ ] `JWT_SECRET`
- [ ] `API_KEY`

### 🗄️ Application Secrets - Production
- [ ] `DATABASE_URL_PROD`
- [ ] `REDIS_URL_PROD`
- [ ] `JWT_SECRET_PROD`
- [ ] `API_KEY_PROD`

### 📧 Notifications (Optional)
- [ ] `SLACK_WEBHOOK_URL`
- [ ] `TEAMS_WEBHOOK_URL`
- [ ] `GITLAB_USER_EMAIL`

---

## Testing Your Configuration

After adding all variables, test the pipeline:

1. **Test with a feature branch** first (not main)
2. **Run only the build stage** initially:
   ```bash
   git commit --allow-empty -m "test: CI pipeline"
   git push origin feature/test-ci
   ```
3. **Check job logs** for any missing variables
4. **Verify secrets are masked** in logs
5. **Test manual deployment** to staging
6. **Finally test production** deployment (with caution)

---

## Additional Resources

- [GitLab CI/CD Variables Documentation](https://docs.gitlab.com/ee/ci/variables/)
- [GCP Service Account Best Practices](https://cloud.google.com/iam/docs/best-practices-service-accounts)
- [SonarCloud Documentation](https://docs.sonarcloud.io/)
- [Snyk Documentation](https://docs.snyk.io/)

---

## Support

If you encounter issues not covered in this guide:

1. Check GitLab CI/CD job logs for detailed error messages
2. Verify all prerequisites are met for each stage
3. Consult the service-specific documentation (GCP, Snyk, SonarCloud)
4. Review GitLab Runner logs if jobs are stuck

---

**Last Updated**: 2026-01-12
**Pipeline Version**: 1.0.0
**Author**: DevOps Team
