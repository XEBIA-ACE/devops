# GitHub Actions Secrets & Variables Setup Checklist

## Quick Setup Guide

This checklist provides all the secrets and variables you need to configure in GitHub to make the CI/CD pipeline operational.

---

## Step 1: Configure GitHub Secrets

**Navigation**: Repository → Settings → Secrets and variables → Actions → Secrets tab → "New repository secret"

### Required Secrets

| # | Secret Name | Required? | Description | How to Obtain | Example Value |
|---|-------------|-----------|-------------|---------------|---------------|
| 1 | `GITHUB_TOKEN` | ✅ **Auto-provided** | GitHub Container Registry authentication | Automatically available in all workflows | N/A - Auto-generated |
| 2 | `DEV_DEPLOY_WEBHOOK` | ✅ **Yes** | Development deployment webhook URL | Your deployment system webhook endpoint | `https://deploy.yourcompany.com/api/deploy/dev` |
| 3 | `STAGING_DEPLOY_WEBHOOK` | ✅ **Yes** | Staging deployment webhook URL | Your deployment system webhook endpoint | `https://deploy.yourcompany.com/api/deploy/staging` |

### Optional Secrets (Notifications)

| # | Secret Name | Required? | Description | How to Obtain | Example Value |
|---|-------------|-----------|-------------|---------------|---------------|
| 4 | `SLACK_WEBHOOK_URL` | ⚪ Optional | Slack failure notifications | Slack App → Incoming Webhooks | `https://hooks.slack.com/services/T00000000/B00000000/XXXX` |
| 5 | `FAILURE_WEBHOOK_URL` | ⚪ Optional | Generic webhook for failure notifications | Your monitoring system webhook | `https://monitoring.yourcompany.com/webhook/pipeline-failure` |

---

## Step 2: Configure GitHub Variables

**Navigation**: Repository → Settings → Secrets and variables → Actions → Variables tab → "New repository variable"

| # | Variable Name | Required? | Description | Example Value |
|---|---------------|-----------|-------------|---------------|
| 1 | `DEV_URL` | ✅ **Yes** | Development environment URL | `https://dev.yourapp.com` |
| 2 | `STAGING_URL` | ✅ **Yes** | Staging environment URL | `https://staging.yourapp.com` |

---

## Step 3: Configure Workflow Permissions

**Navigation**: Repository → Settings → Actions → General → Workflow permissions

- [x] **Read and write permissions** ← Select this
- [ ] Read repository contents and packages permissions
- [x] **Allow GitHub Actions to create and approve pull requests** ← Check this

**Why**: These permissions allow the workflow to push Docker images to GitHub Container Registry (GHCR).

---

## Step 4: Create GitHub Environments

**Navigation**: Repository → Settings → Environments → "New environment"

### Environment 1: Development

**Create Environment**:
- Name: `development`
- Deployment branches: Select "Selected branches" → Add `develop`
- Protection rules: None (allow auto-deploy)

**Why**: Tracks development deployments and provides deployment history.

### Environment 2: Staging

**Create Environment**:
- Name: `staging`
- Deployment branches: Select "Selected branches" → Add `staging`
- Protection rules (Recommended):
  - [x] Required reviewers: Add team leads or senior developers
  - [x] Wait timer: 5 minutes (optional)

**Why**: Provides a safety gate before staging deployments and tracks staging deployment history.

---

## Detailed Setup Instructions

### How to Get Slack Webhook URL

1. Go to your Slack workspace
2. Click on workspace name → Settings & administration → Manage apps
3. Search for "Incoming Webhooks" and click "Add to Slack"
4. Select the channel where you want notifications (e.g., `#deployments`)
5. Click "Add Incoming WebHooks integration"
6. Copy the Webhook URL (looks like: `https://hooks.slack.com/services/...`)
7. Add as `SLACK_WEBHOOK_URL` secret in GitHub

### How to Configure Deployment Webhooks

Your deployment webhooks should accept POST requests with this JSON payload:

```json
{
  "environment": "development",
  "image": "ghcr.io/org/repo:develop-abc123f",
  "commit": "abc123f",
  "branch": "develop",
  "actor": "username"
}
```

**Example Webhook Implementation** (Node.js/Express):
```javascript
app.post('/api/deploy/dev', (req, res) => {
  const { environment, image, commit, branch, actor } = req.body;

  // Trigger your deployment logic here
  // e.g., kubectl set image deployment/app app=${image}

  res.json({ status: 'success', message: 'Deployment initiated' });
});
```

---

## Verification Steps

### 1. Verify Secrets Are Set
```bash
# Cannot view secret values directly, but can verify they exist
# Go to: Settings → Secrets and variables → Actions → Secrets
# You should see all required secrets listed
```

### 2. Verify Variables Are Set
```bash
# Go to: Settings → Secrets and variables → Actions → Variables
# You should see:
# - DEV_URL = https://dev.yourapp.com
# - STAGING_URL = https://staging.yourapp.com
```

### 3. Verify Workflow Permissions
```bash
# Go to: Settings → Actions → General → Workflow permissions
# Should show: "Read and write permissions" selected
```

### 4. Verify Environments Exist
```bash
# Go to: Settings → Environments
# You should see:
# - development (with develop branch restriction)
# - staging (with staging branch restriction and optional protection rules)
```

### 5. Test the Pipeline
```bash
# Push a change to develop branch
git checkout develop
echo "# Test" >> README.md
git add README.md
git commit -m "test: verify CI/CD pipeline"
git push origin develop

# Go to Actions tab and verify:
# - Build job succeeds
# - Quality gate job succeeds
# - Container build & scan job succeeds
# - Deploy development job succeeds
# - Image appears in Packages section
```

---

## Configuration Matrix

### Minimal Configuration (Required Only)

Use this if you only want the core pipeline without notifications:

**Secrets**:
- `GITHUB_TOKEN` (auto)
- `DEV_DEPLOY_WEBHOOK`
- `STAGING_DEPLOY_WEBHOOK`

**Variables**:
- `DEV_URL`
- `STAGING_URL`

**Result**: Pipeline runs, builds, scans, deploys, but no failure notifications.

### Full Configuration (Recommended)

Include all optional secrets for complete monitoring:

**Secrets**:
- `GITHUB_TOKEN` (auto)
- `DEV_DEPLOY_WEBHOOK`
- `STAGING_DEPLOY_WEBHOOK`
- `SLACK_WEBHOOK_URL` ← Add this
- `FAILURE_WEBHOOK_URL` ← Add this

**Variables**:
- `DEV_URL`
- `STAGING_URL`

**Result**: Complete pipeline with Slack and webhook notifications on failures.

---

## Troubleshooting

### Issue: "GITHUB_TOKEN does not have permission to push to ghcr.io"

**Solution**:
1. Go to Settings → Actions → General → Workflow permissions
2. Select "Read and write permissions"
3. Save and re-run the workflow

### Issue: "Secret not found: DEV_DEPLOY_WEBHOOK"

**Solution**:
1. Verify secret name is exactly `DEV_DEPLOY_WEBHOOK` (case-sensitive)
2. Check you added it under "Repository secrets" not "Environment secrets"
3. Secrets are available immediately after adding, no waiting required

### Issue: "Environment not found: development"

**Solution**:
1. Go to Settings → Environments
2. Click "New environment"
3. Name must be exactly `development` (lowercase)
4. Configure deployment branches to include `develop`

### Issue: "Variable not found: DEV_URL"

**Solution**:
1. Verify you're in the "Variables" tab, not "Secrets" tab
2. Variable name must be exactly `DEV_URL` (case-sensitive)
3. Go to Settings → Secrets and variables → Actions → Variables tab

---

## Security Best Practices

### 1. Secrets Management
- ✅ Never commit secrets to git
- ✅ Use GitHub secrets for all sensitive data
- ✅ Rotate webhook URLs annually
- ✅ Use environment-specific secrets when needed

### 2. Webhook Security
- ✅ Use HTTPS endpoints only
- ✅ Consider adding authentication headers to webhook payloads
- ✅ Implement webhook signature verification on receiving end
- ✅ Rate-limit webhook endpoints

### 3. Environment Protection
- ✅ Require approvals for staging deployments
- ✅ Restrict who can approve deployments
- ✅ Use branch protection rules
- ✅ Enable deployment branch policies

### 4. Access Control
- ✅ Limit repository admin access
- ✅ Use CODEOWNERS for sensitive files
- ✅ Enable branch protection on main/staging
- ✅ Require pull request reviews

---

## Advanced: Organization-Level Secrets

If you have multiple repositories using the same secrets:

1. Go to Organization Settings → Secrets and variables → Actions
2. Create organization-level secrets
3. Select which repositories can access each secret
4. Benefits:
   - Centralized secret management
   - Consistent webhook URLs across projects
   - Easier rotation and updates

**Organization Secrets to Consider**:
- `ORG_SLACK_WEBHOOK` - Shared Slack channel for all deployments
- `ORG_MONITORING_WEBHOOK` - Centralized monitoring system

---

## Complete Setup Checklist

Use this checklist to verify your setup is complete:

- [ ] Added `DEV_DEPLOY_WEBHOOK` secret
- [ ] Added `STAGING_DEPLOY_WEBHOOK` secret
- [ ] Added `SLACK_WEBHOOK_URL` secret (optional but recommended)
- [ ] Added `FAILURE_WEBHOOK_URL` secret (optional)
- [ ] Added `DEV_URL` variable
- [ ] Added `STAGING_URL` variable
- [ ] Set workflow permissions to "Read and write"
- [ ] Enabled "Allow GitHub Actions to create and approve pull requests"
- [ ] Created `development` environment
- [ ] Created `staging` environment
- [ ] Configured `develop` branch as deployment branch for development environment
- [ ] Configured `staging` branch as deployment branch for staging environment
- [ ] Added required reviewers to staging environment (recommended)
- [ ] Tested pipeline by pushing to `develop` branch
- [ ] Verified Docker image appears in Packages section
- [ ] Verified deployment webhook receives correct payload
- [ ] Verified Slack notification on failure (if configured)
- [ ] Reviewed GitHub Security tab for Trivy scan results

---

## Quick Reference Commands

### View GitHub CLI Secrets
```bash
# Install GitHub CLI
gh auth login

# List secrets (cannot view values, only names)
gh secret list

# Add a secret via CLI
gh secret set DEV_DEPLOY_WEBHOOK --body "https://deploy.com/dev"

# List variables
gh variable list

# Add a variable via CLI
gh variable set DEV_URL --body "https://dev.yourapp.com"
```

### Test Webhook Locally
```bash
# Test deployment webhook
curl -X POST "https://your-deployment-endpoint.com/deploy/dev" \
  -H "Content-Type: application/json" \
  -d '{
    "environment": "development",
    "image": "ghcr.io/org/repo:test",
    "commit": "abc123",
    "branch": "develop",
    "actor": "testuser"
  }'

# Test Slack webhook
curl -X POST "YOUR_SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Test notification from pipeline setup"
  }'
```

---

## Support Resources

- **GitHub Secrets Documentation**: https://docs.github.com/en/actions/security-guides/encrypted-secrets
- **GitHub Environments**: https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment
- **GHCR Authentication**: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- **Slack Incoming Webhooks**: https://api.slack.com/messaging/webhooks

---

**Last Updated**: 2026-01-20
**Configuration Version**: 1.0.0
