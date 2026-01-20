# GitHub Actions CI/CD Pipeline - Setup Guide

## Overview
This guide provides step-by-step instructions to configure the GitHub Actions CI/CD pipeline for your Python/Maven application with comprehensive security scanning, quality gates, and automated deployments.

---

## Pipeline Architecture

**Linear Flow:**
```
Build → Quality Gate → Security Scan → Container Build & Scan → Deploy (Dev/Staging) → Notify on Failure
```

**Key Features:**
- Optimized Maven build with aggressive dependency caching
- Quality gates: PMD, SpotBugs (pipeline fails if checks don't pass)
- Security scanning: Aqua Trivy, OWASP Dependency-Check
- Container hardening with image scanning
- Linear deployment to Development and Staging environments
- Slack/Webhook notifications on pipeline failure

---

## Prerequisites

1. **GitHub Repository** with the following structure:
   ```
   .
   ├── .github/workflows/ci-cd-pipeline.yml
   ├── pom.xml
   ├── Dockerfile (or Dockerfile.maven)
   └── src/
   ```

2. **GitHub Container Registry (GHCR)** access (included with GitHub)

3. **Maven Project** configured with:
   - PMD plugin
   - SpotBugs plugin
   - OWASP Dependency-Check plugin

---

## Required GitHub Secrets

Navigate to: **Repository Settings → Secrets and variables → Actions → New repository secret**

### 1. Notification Secrets

| Secret Name | Description | Required | Example/Format |
|-------------|-------------|----------|----------------|
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL for failure notifications | Optional | `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX` |
| `FAILURE_WEBHOOK_URL` | Generic webhook URL for failure notifications | Optional | `https://your-webhook-service.com/notify` |

### 2. Deployment Secrets

| Secret Name | Description | Required | Example/Format |
|-------------|-------------|----------|----------------|
| `DEV_DEPLOY_WEBHOOK` | Webhook URL to trigger development deployment | Optional | `https://deploy.yourservice.com/dev/webhook` |
| `STAGING_DEPLOY_WEBHOOK` | Webhook URL to trigger staging deployment | Optional | `https://deploy.yourservice.com/staging/webhook` |

### 3. Registry Secrets

| Secret Name | Description | Required | Example/Format |
|-------------|-------------|----------|----------------|
| `GITHUB_TOKEN` | Automatically provided by GitHub Actions | ✓ Auto | N/A - Automatically available |

---

## Required GitHub Variables

Navigate to: **Repository Settings → Secrets and variables → Actions → Variables tab → New repository variable**

| Variable Name | Description | Example Value |
|---------------|-------------|---------------|
| `DEV_URL` | Development environment URL | `https://dev.myapp.com` |
| `STAGING_URL` | Staging environment URL | `https://staging.myapp.com` |

---

## GitHub Environments Configuration

Configure deployment environments for tracking and protection rules:

### Setup Steps:
1. Navigate to: **Repository Settings → Environments**
2. Create two environments:

#### Development Environment
- **Name:** `development`
- **Deployment branches:** `develop` branch only
- **Environment URL:** Set to `${{ vars.DEV_URL }}`
- **Protection rules:** (Optional) Add required reviewers if needed

#### Staging Environment
- **Name:** `staging`
- **Deployment branches:** `staging` branch only
- **Environment URL:** Set to `${{ vars.STAGING_URL }}`
- **Protection rules:** (Optional) Add required reviewers, wait timer

---

## Maven POM.xml Configuration

Ensure your `pom.xml` includes the required plugins:

### 1. PMD Plugin
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-pmd-plugin</artifactId>
    <version>3.21.2</version>
    <configuration>
        <targetJdk>17</targetJdk>
        <failOnViolation>true</failOnViolation>
        <printFailingErrors>true</printFailingErrors>
    </configuration>
</plugin>
```

### 2. SpotBugs Plugin
```xml
<plugin>
    <groupId>com.github.spotbugs</groupId>
    <artifactId>spotbugs-maven-plugin</artifactId>
    <version>4.8.3.0</version>
    <configuration>
        <effort>Max</effort>
        <threshold>Medium</threshold>
        <failOnError>true</failOnError>
    </configuration>
</plugin>
```

### 3. OWASP Dependency-Check Plugin
```xml
<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>9.0.9</version>
    <configuration>
        <failBuildOnCVSS>7</failBuildOnCVSS>
        <suppressionFiles>
            <suppressionFile>dependency-check-suppressions.xml</suppressionFile>
        </suppressionFiles>
    </configuration>
</plugin>
```

---

## Dockerfile Requirements

Your Dockerfile should be optimized for Maven builds. Example:

```dockerfile
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

## Branch Strategy

The pipeline is configured for the following branching model:

| Branch | Triggers | Deployment Target |
|--------|----------|-------------------|
| `develop` | Push, Pull Request | Development environment |
| `staging` | Push, Pull Request | Staging environment |
| `main` | Push, Pull Request | (Configure as needed) |

**Note:** Adjust the branches in the workflow file if your naming convention differs.

---

## Slack Webhook Setup (Optional)

### 1. Create Slack Incoming Webhook
1. Go to: https://api.slack.com/messaging/webhooks
2. Click "Create your Slack app"
3. Choose "From scratch"
4. Select your workspace
5. Navigate to "Incoming Webhooks" and activate
6. Click "Add New Webhook to Workspace"
7. Select the channel for notifications
8. Copy the Webhook URL

### 2. Add to GitHub Secrets
- Add the webhook URL as `SLACK_WEBHOOK_URL` secret

---

## Deployment Webhook Integration

The pipeline sends deployment webhooks with the following payload:

```json
{
  "environment": "development|staging",
  "image": "ghcr.io/owner/repo:sha",
  "commit": "commit-sha",
  "branch": "branch-name",
  "actor": "github-username"
}
```

**Customize the deployment step** in the workflow file to match your deployment infrastructure:
- Kubernetes: `kubectl set image deployment/myapp myapp=$IMAGE`
- Docker Compose: `docker-compose pull && docker-compose up -d`
- Custom API: Update the webhook payload and endpoint

---

## GitHub Container Registry Permissions

### Repository Permissions
Ensure the repository has GHCR access:
1. Navigate to: **Repository Settings → Actions → General**
2. Under "Workflow permissions", select:
   - ✓ **Read and write permissions**
   - ✓ **Allow GitHub Actions to create and approve pull requests**

### Package Visibility
After the first successful push:
1. Navigate to: **Your Profile → Packages**
2. Select the package
3. **Package Settings → Change visibility** (Public/Private as needed)
4. Connect the package to the repository if not auto-linked

---

## Pipeline Execution Flow

### 1. Build Stage
- Checks out code
- Sets up JDK 17 with Maven caching
- Caches Maven dependencies (~/.m2/repository)
- Builds the application (`mvn clean package`)
- Runs unit tests (`mvn test`)
- Uploads JAR artifacts

### 2. Quality Gate Stage
- Runs PMD static analysis (`mvn pmd:check`)
- Runs SpotBugs analysis (`mvn spotbugs:check`)
- **Pipeline fails if checks don't pass**
- Uploads analysis reports as artifacts

### 3. Security Scan Stage
- Downloads build artifacts
- Runs OWASP Dependency-Check with CVSS threshold 7
- **Pipeline fails if critical vulnerabilities found**
- Uploads dependency check report

### 4. Container Build & Scan Stage
- Builds Docker image
- Runs Aqua Trivy security scan
- **Pipeline fails if CRITICAL/HIGH vulnerabilities found**
- Uploads scan results to GitHub Security tab
- Pushes image to GHCR with tags:
  - `branch-shortsha` (e.g., `develop-a1b2c3d`)
  - `branch-name`
  - `latest` (for default branch)

### 5. Deployment Stage
- **Development:** Deploys on push to `develop` branch
- **Staging:** Deploys on push to `staging` branch
- Sends deployment webhook
- Tracks deployment in GitHub Environments

### 6. Notification Stage
- Triggers **only on pipeline failure**
- Sends Slack notification (if configured)
- Sends generic webhook (if configured)

---

## Verification Steps

### 1. Validate Configuration
After setup, verify:
```bash
# Check secrets are set
gh secret list

# Check variables are set
gh variable list

# Test workflow syntax
gh workflow view ci-cd-pipeline.yml
```

### 2. Test Pipeline
1. Create a test commit on `develop` branch
2. Monitor the workflow: **Actions tab → CI/CD Pipeline**
3. Verify each stage passes
4. Check artifacts are uploaded
5. Confirm image is pushed to GHCR
6. Validate deployment to Development environment

### 3. Verify Notifications
Trigger a failure to test notifications:
```bash
# Temporarily introduce a test failure or PMD violation
git commit -m "test: trigger failure notification"
git push
```

---

## Troubleshooting

### Common Issues

#### 1. Maven Cache Not Working
**Symptom:** Dependencies downloaded every run
**Solution:**
- Verify `pom.xml` exists and hasn't changed
- Check cache key in workflow file
- Ensure sufficient Actions cache storage

#### 2. GHCR Push Permission Denied
**Symptom:** `403 Forbidden` when pushing to GHCR
**Solution:**
- Verify workflow permissions (Settings → Actions → General)
- Ensure `GITHUB_TOKEN` has `packages: write` permission
- Check package visibility settings

#### 3. Quality Gate Failures
**Symptom:** PMD/SpotBugs failing the pipeline
**Solution:**
- Run locally: `mvn pmd:check spotbugs:check`
- Fix violations or adjust thresholds in `pom.xml`
- Add suppressions if needed

#### 4. OWASP Dependency-Check Timeout
**Symptom:** Dependency check taking too long
**Solution:**
- Add NVD API key for faster CVE database updates
- Adjust `failBuildOnCVSS` threshold
- Use suppression file for false positives

#### 5. Trivy Scan Failures
**Symptom:** Image scan failing on vulnerabilities
**Solution:**
- Update base image to latest patched version
- Review Trivy results in GitHub Security tab
- Add `.trivyignore` file for known false positives

#### 6. Deployment Not Triggering
**Symptom:** Deployment job skipped
**Solution:**
- Verify branch name matches workflow condition
- Ensure push event (not pull request)
- Check GitHub Environment restrictions

---

## Security Best Practices

1. **Secrets Management**
   - Never commit secrets to the repository
   - Rotate secrets regularly
   - Use environment-specific secrets

2. **Image Security**
   - Use minimal base images (Alpine, Distroless)
   - Scan images before deployment
   - Keep base images updated

3. **Access Control**
   - Enable branch protection rules
   - Require reviews for production deployments
   - Use GitHub Environment protection rules

4. **Audit and Monitoring**
   - Review workflow run logs regularly
   - Monitor security scan results
   - Track deployment history via GitHub Environments

---

## Customization Options

### Adjust Quality Thresholds
Edit the workflow file to change failure conditions:
```yaml
# Make PMD non-blocking (not recommended)
- name: Run PMD analysis
  run: mvn pmd:check
  continue-on-error: true
```

### Add Additional Environments
1. Create new environment in GitHub Settings
2. Add deployment job to workflow:
```yaml
deploy-production:
  name: Deploy to Production
  runs-on: ubuntu-latest
  needs: container-build-scan
  if: github.ref == 'refs/heads/main'
  environment:
    name: production
    url: ${{ vars.PROD_URL }}
  steps:
    # Add deployment steps
```

### Custom Notification Channels
Add email, Teams, or other notification services:
```yaml
- name: Send email notification
  uses: dawidd6/action-send-mail@v3
  with:
    server_address: smtp.gmail.com
    server_port: 587
    username: ${{ secrets.EMAIL_USERNAME }}
    password: ${{ secrets.EMAIL_PASSWORD }}
    subject: Pipeline Failed
    body: Workflow failed for ${{ github.repository }}
    to: team@example.com
```

---

## Performance Optimization

The pipeline implements several optimizations:

1. **Aggressive Caching**
   - Maven dependencies (~/.m2/repository)
   - Docker layer caching (GitHub Actions Cache)
   - Setup-java built-in Maven cache

2. **Artifact Reuse**
   - Build artifacts shared across jobs
   - Avoids rebuilding in each stage

3. **Parallel Execution**
   - Quality gate and security scan run after build
   - Independent checks don't block each other

**Expected Runtime:**
- First run: 8-12 minutes (no cache)
- Subsequent runs: 3-6 minutes (with cache)
- Cache hit rate: ~85-95%

---

## Support and Maintenance

### Regular Maintenance Tasks
- Update GitHub Actions versions quarterly
- Review and update Maven plugin versions
- Rotate secrets and webhooks annually
- Review security scan suppressions monthly

### Monitoring
- Check workflow success rate: Actions → Insights
- Review artifact storage usage: Settings → Actions → Storage
- Monitor GHCR storage: Profile → Packages

---

## Quick Reference

### Secrets Checklist
- [ ] SLACK_WEBHOOK_URL (optional)
- [ ] FAILURE_WEBHOOK_URL (optional)
- [ ] DEV_DEPLOY_WEBHOOK (optional)
- [ ] STAGING_DEPLOY_WEBHOOK (optional)

### Variables Checklist
- [ ] DEV_URL
- [ ] STAGING_URL

### GitHub Configuration
- [ ] Environments created (development, staging)
- [ ] Workflow permissions set (read/write)
- [ ] Branch protection rules configured

### Maven Configuration
- [ ] PMD plugin added to pom.xml
- [ ] SpotBugs plugin added to pom.xml
- [ ] OWASP Dependency-Check plugin added to pom.xml

### Repository Files
- [ ] .github/workflows/ci-cd-pipeline.yml
- [ ] Dockerfile
- [ ] pom.xml
- [ ] dependency-check-suppressions.xml (optional)

---

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Maven PMD Plugin](https://maven.apache.org/plugins/maven-pmd-plugin/)
- [SpotBugs Maven Plugin](https://spotbugs.github.io/spotbugs-maven-plugin/)
- [OWASP Dependency-Check](https://jeremylong.github.io/DependencyCheck/dependency-check-maven/)
- [Aqua Trivy](https://github.com/aquasecurity/trivy)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

---

## Contact and Support

For issues with this pipeline:
1. Review the Troubleshooting section
2. Check GitHub Actions logs: Actions tab → Failed workflow → Job logs
3. Review security scan reports in Artifacts section
4. Consult your DevOps team or create a repository issue

---

**Pipeline Version:** 1.0.0
**Last Updated:** 2026-01-20
**Maintained By:** DevOps Team
