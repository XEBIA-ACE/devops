# GitHub Actions CI/CD Pipeline - Setup Guide

This guide provides step-by-step instructions for configuring the production-grade CI/CD pipeline for your Python/Maven application.

## Overview

The pipeline implements a linear Code-to-Registry flow with the following stages:
1. **Build & Test** - Maven build with aggressive dependency caching
2. **Static Analysis & Security** - PMD, SpotBugs, and OWASP Dependency-Check
3. **Container Build & Security Scan** - Docker image build with Aqua Security Trivy scanning
4. **Deployment** - Push-to-deploy for Development and Staging environments
5. **Failure Notification** - Slack/Webhook alerts on pipeline failures

## Prerequisites

- GitHub repository with admin access
- GitHub Container Registry (GHCR) enabled
- Maven-based Java application
- Docker configuration (Dockerfile.maven)

## Required Secrets

Navigate to your GitHub repository: **Settings → Secrets and variables → Actions → New repository secret**

### 1. NVD_API_KEY
**Purpose**: National Vulnerability Database API access for OWASP Dependency-Check

**How to obtain**:
1. Visit https://nvd.nist.gov/developers/request-an-api-key
2. Request an API key (free)
3. Add the received key to GitHub Secrets

**Secret Name**: `NVD_API_KEY`
**Required**: Yes (Quality Gate will fail without it)

---

### 2. SLACK_WEBHOOK_URL
**Purpose**: Send pipeline failure notifications to Slack

**How to obtain**:
1. Go to your Slack workspace
2. Navigate to: https://api.slack.com/messaging/webhooks
3. Create an Incoming Webhook for your desired channel
4. Copy the webhook URL

**Secret Name**: `SLACK_WEBHOOK_URL`
**Required**: Optional (notifications won't be sent if not configured)

---

### 3. FAILURE_WEBHOOK_URL
**Purpose**: Generic webhook for pipeline failure notifications (alternative to Slack)

**Format**: `https://your-webhook-endpoint.com/notifications`

**Secret Name**: `FAILURE_WEBHOOK_URL`
**Required**: Optional (alternative to Slack notifications)

---

### 4. DEV_DEPLOY_WEBHOOK
**Purpose**: Webhook endpoint to trigger deployment to Development environment

**Format**:
```
https://your-deployment-system.com/deploy
```

**Payload sent**:
```json
{
  "environment": "development",
  "image": "ghcr.io/your-org/your-repo:commit-sha",
  "commit": "commit-sha",
  "branch": "develop",
  "actor": "github-username"
}
```

**Secret Name**: `DEV_DEPLOY_WEBHOOK`
**Required**: Optional (deployment step will show warning if not configured)

---

### 5. STAGING_DEPLOY_WEBHOOK
**Purpose**: Webhook endpoint to trigger deployment to Staging environment

**Format**: Same as DEV_DEPLOY_WEBHOOK
**Payload**: Same structure with `"environment": "staging"`

**Secret Name**: `STAGING_DEPLOY_WEBHOOK`
**Required**: Optional (deployment step will show warning if not configured)

---

### 6. GITHUB_TOKEN (Automatic)
**Purpose**: Authentication for GitHub Container Registry and GitHub API

**Note**: This is automatically provided by GitHub Actions. **DO NOT manually configure this secret.**

---

## Required Variables

Navigate to your GitHub repository: **Settings → Secrets and variables → Actions → Variables tab → New repository variable**

### 1. DEV_URL
**Purpose**: Development environment URL for tracking and display

**Example**: `https://dev.yourapp.com`

**Variable Name**: `DEV_URL`
**Required**: Optional (recommended for environment tracking)

---

### 2. STAGING_URL
**Purpose**: Staging environment URL for tracking and display

**Example**: `https://staging.yourapp.com`

**Variable Name**: `STAGING_URL`
**Required**: Optional (recommended for environment tracking)

---

## GitHub Environments Configuration

The pipeline uses GitHub Environments to track deployments. Set these up for enhanced visibility:

### 1. Create Development Environment
1. Go to: **Settings → Environments → New environment**
2. Name: `development`
3. Configure environment URL: `${{ vars.DEV_URL }}`
4. (Optional) Add protection rules:
   - Required reviewers: None (auto-deploy on push to `develop` branch)
   - Deployment branches: `develop` only

### 2. Create Staging Environment
1. Go to: **Settings → Environments → New environment**
2. Name: `staging`
3. Configure environment URL: `${{ vars.STAGING_URL }}`
4. (Optional) Add protection rules:
   - Required reviewers: Add reviewers for manual approval
   - Deployment branches: `staging` only

---

## Maven Configuration

Ensure your `pom.xml` includes the required plugins:

### PMD Plugin
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-pmd-plugin</artifactId>
    <version>3.21.0</version>
    <configuration>
        <failOnViolation>true</failOnViolation>
        <printFailingErrors>true</printFailingErrors>
    </configuration>
</plugin>
```

### SpotBugs Plugin
```xml
<plugin>
    <groupId>com.github.spotbugs</groupId>
    <artifactId>spotbugs-maven-plugin</artifactId>
    <version>4.7.3.6</version>
    <configuration>
        <failOnError>true</failOnError>
    </configuration>
</plugin>
```

### OWASP Dependency-Check Plugin
```xml
<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>8.4.0</version>
    <configuration>
        <failBuildOnCVSS>7</failBuildOnCVSS>
        <suppressionFiles>
            <suppressionFile>dependency-check-suppressions.xml</suppressionFile>
        </suppressionFiles>
    </configuration>
</plugin>
```

---

## Docker Configuration

Ensure you have a `Dockerfile.maven` in your repository root:

```dockerfile
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

## Branch Strategy

The pipeline is configured for the following branch strategy:

| Branch | Trigger | Actions |
|--------|---------|---------|
| `main` | Push | Build, Test, Quality Gate, Build & Scan Image (no deployment) |
| `develop` | Push | Full pipeline → Deploy to Development |
| `staging` | Push | Full pipeline → Deploy to Staging |
| All branches | Pull Request | Build, Test, Quality Gate only |

---

## Pipeline Execution Flow

```
Push to develop/staging branch
    ↓
1. Build & Test (Maven with caching)
    ↓
2. Static Analysis & Security (PMD, SpotBugs, OWASP)
    ↓ [Fails on violations]
3. Container Build & Security Scan (Docker + Trivy)
    ↓ [Fails on CRITICAL/HIGH vulnerabilities]
4. Push Image to GHCR (tagged with commit SHA)
    ↓
5. Deploy to Environment (webhook-based)
    ↓
6. [On Failure] Send Notifications (Slack/Webhook)
```

---

## Verification Checklist

After configuration, verify the following:

- [ ] All required secrets are configured in GitHub Settings
- [ ] Environment variables (DEV_URL, STAGING_URL) are set
- [ ] GitHub Environments (development, staging) are created
- [ ] Maven plugins (PMD, SpotBugs, OWASP) are in pom.xml
- [ ] Dockerfile.maven exists in repository root
- [ ] GHCR package visibility is set correctly (private/public)
- [ ] Slack/Webhook endpoints are accessible
- [ ] Deployment webhooks are configured and tested

---

## Testing the Pipeline

1. **Test on Pull Request**:
   ```bash
   git checkout -b test-pipeline
   git commit --allow-empty -m "Test pipeline"
   git push origin test-pipeline
   # Create PR to main/develop
   ```

2. **Test Development Deployment**:
   ```bash
   git checkout develop
   git commit --allow-empty -m "Test dev deployment"
   git push origin develop
   ```

3. **Test Staging Deployment**:
   ```bash
   git checkout staging
   git commit --allow-empty -m "Test staging deployment"
   git push origin staging
   ```

---

## Monitoring and Artifacts

### Available Artifacts
The pipeline produces the following artifacts (downloadable from Actions run):
- **test-results**: JUnit test reports
- **build-artifacts**: Compiled JAR files
- **pmd-report**: PMD static analysis results
- **spotbugs-report**: SpotBugs analysis results
- **dependency-check-report**: OWASP vulnerability report

### GitHub Security Integration
- Trivy scan results are uploaded to **Security → Code scanning alerts**
- View vulnerability findings directly in the GitHub Security tab

### Container Registry
- Images are pushed to: `ghcr.io/<your-org>/<your-repo>:<commit-sha>`
- View packages: **Packages** tab in your GitHub repository

---

## Performance Optimizations

The pipeline includes several optimizations for speed:

1. **Aggressive Maven Caching**:
   - Caches `~/.m2/repository` and `~/.m2/wrapper`
   - Cache key based on `pom.xml` hash
   - Restores partial matches for faster builds

2. **Docker Layer Caching**:
   - Uses GitHub Actions cache (type=gha)
   - Caches all layers (mode=max)
   - Significantly reduces image build time

3. **Build Optimization Flags**:
   - `-B`: Batch mode (non-interactive)
   - `-ntp`: No transfer progress (cleaner logs)
   - `-XX:+TieredCompilation -XX:TieredStopAtLevel=1`: Faster JVM compilation

---

## Troubleshooting

### Pipeline Fails on PMD/SpotBugs
- Review the uploaded artifacts for detailed reports
- Fix code quality issues or update plugin configuration in `pom.xml`
- Consider adjusting rulesets if too strict

### OWASP Dependency-Check Fails
- Check if `NVD_API_KEY` is configured correctly
- Review the dependency-check-report.html artifact
- Add suppressions if false positives exist

### Trivy Security Scan Fails
- Review vulnerabilities in GitHub Security tab
- Update base Docker image to patched version
- Consider using `distroless` or `alpine` base images

### Deployment Webhook Timeout
- Verify webhook endpoint is accessible from GitHub Actions
- Check webhook logs on your deployment system
- Ensure webhook returns HTTP 200 within 30 seconds

### Image Push to GHCR Fails
- Verify GHCR is enabled for your repository
- Check package visibility settings
- Ensure GITHUB_TOKEN has `packages: write` permission (automatic in this pipeline)

---

## Security Considerations

1. **Secrets Management**:
   - Never commit secrets to the repository
   - Use GitHub Secrets for all sensitive data
   - Rotate API keys and webhooks periodically

2. **Image Security**:
   - Pipeline fails on CRITICAL/HIGH vulnerabilities
   - Regularly update base images
   - Monitor GitHub Security alerts

3. **Deployment Security**:
   - Use HTTPS for all webhook endpoints
   - Implement webhook signature verification
   - Restrict network access to deployment systems

4. **Access Control**:
   - Limit repository admin access
   - Use environment protection rules for production
   - Enable branch protection for main/staging branches

---

## Next Steps

1. Configure all required secrets and variables
2. Set up GitHub Environments
3. Test the pipeline with a sample commit
4. Monitor first few runs for any issues
5. Configure Slack notifications for team visibility
6. Set up deployment webhooks for automated deployments

---

## Support and Feedback

For issues or questions:
- Review GitHub Actions logs for detailed error messages
- Check artifact uploads for analysis reports
- Consult GitHub Actions documentation: https://docs.github.com/en/actions

---

## Quick Reference

### Secrets Summary
| Secret Name | Required | Purpose |
|-------------|----------|---------|
| NVD_API_KEY | Yes | OWASP vulnerability database access |
| SLACK_WEBHOOK_URL | Optional | Slack failure notifications |
| FAILURE_WEBHOOK_URL | Optional | Generic webhook notifications |
| DEV_DEPLOY_WEBHOOK | Optional | Development deployment trigger |
| STAGING_DEPLOY_WEBHOOK | Optional | Staging deployment trigger |

### Variables Summary
| Variable Name | Required | Purpose |
|---------------|----------|---------|
| DEV_URL | Optional | Development environment URL |
| STAGING_URL | Optional | Staging environment URL |

### Branch Behavior
| Branch | Build | Test | Quality | Image | Deploy |
|--------|-------|------|---------|-------|--------|
| main | ✅ | ✅ | ✅ | ✅ | ❌ |
| develop | ✅ | ✅ | ✅ | ✅ | ✅ Dev |
| staging | ✅ | ✅ | ✅ | ✅ | ✅ Staging |
| PR | ✅ | ✅ | ✅ | ❌ | ❌ |
