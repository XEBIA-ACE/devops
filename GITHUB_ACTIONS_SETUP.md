# CI/CD Pipeline Setup Guide

## Overview
This guide provides step-by-step instructions for setting up the GitHub Actions CI/CD pipeline for your Python/Maven application.

## Prerequisites
- GitHub repository with admin access
- GitHub Container Registry (GHCR) access enabled
- Java 17 or higher
- Maven 3.8 or higher
- Docker

---

## Required GitHub Secrets

Navigate to your repository: **Settings → Secrets and variables → Actions → New repository secret**

### 1. GitHub Token (Automatic)
- **Secret Name:** `GITHUB_TOKEN`
- **Description:** Automatically provided by GitHub Actions
- **Usage:** Authentication for GHCR push operations
- **Action Required:** None - this is automatically available

### 2. Slack Webhook (Optional)
- **Secret Name:** `SLACK_WEBHOOK_URL`
- **Description:** Incoming webhook URL for Slack notifications on pipeline failures
- **How to Obtain:**
  1. Go to your Slack workspace
  2. Navigate to Apps → Incoming Webhooks
  3. Click "Add to Slack"
  4. Select a channel and copy the webhook URL
- **Example Value:** `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX`

### 3. Generic Failure Webhook (Optional)
- **Secret Name:** `FAILURE_WEBHOOK_URL`
- **Description:** Generic webhook endpoint for custom failure notifications
- **Example Value:** `https://your-monitoring-system.com/webhooks/pipeline-failure`

### 4. Development Deployment Webhook
- **Secret Name:** `DEV_DEPLOY_WEBHOOK`
- **Description:** Webhook URL to trigger deployment to development environment
- **Example Value:** `https://your-deployment-system.com/deploy/dev`

### 5. Staging Deployment Webhook
- **Secret Name:** `STAGING_DEPLOY_WEBHOOK`
- **Description:** Webhook URL to trigger deployment to staging environment
- **Example Value:** `https://your-deployment-system.com/deploy/staging`

---

## Required GitHub Variables

Navigate to your repository: **Settings → Secrets and variables → Actions → Variables tab → New repository variable**

### 1. Development Environment URL
- **Variable Name:** `DEV_URL`
- **Description:** URL of your development environment
- **Example Value:** `https://dev.yourapp.com`

### 2. Staging Environment URL
- **Variable Name:** `STAGING_URL`
- **Description:** URL of your staging environment
- **Example Value:** `https://staging.yourapp.com`

---

## GitHub Environments Setup

### 1. Create Development Environment
1. Go to **Settings → Environments → New environment**
2. Name: `development`
3. Configure protection rules (optional):
   - Required reviewers: None (auto-deploy on push to `develop` branch)
   - Wait timer: 0 minutes
   - Deployment branches: `develop`

### 2. Create Staging Environment
1. Go to **Settings → Environments → New environment**
2. Name: `staging`
3. Configure protection rules (recommended):
   - Required reviewers: Add team leads/senior developers
   - Wait timer: Optional (e.g., 5 minutes)
   - Deployment branches: `staging`

---

## GitHub Container Registry (GHCR) Setup

### 1. Enable Package Permissions
1. Go to **Settings → Actions → General**
2. Scroll to **Workflow permissions**
3. Select **Read and write permissions**
4. Check **Allow GitHub Actions to create and approve pull requests**
5. Click **Save**

### 2. Verify Package Visibility
After the first successful pipeline run:
1. Go to your repository main page
2. Click **Packages** (right sidebar)
3. Select your container image
4. Go to **Package settings**
5. Set visibility as needed (Private recommended for production)

---

## Maven Configuration

### 1. Update pom.xml
Ensure your `pom.xml` includes the required plugins for PMD and SpotBugs:

```xml
<build>
    <plugins>
        <!-- PMD Plugin -->
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-pmd-plugin</artifactId>
            <version>3.21.2</version>
            <configuration>
                <targetJdk>17</targetJdk>
                <failOnViolation>true</failOnViolation>
                <printFailingErrors>true</printFailingErrors>
            </configuration>
            <executions>
                <execution>
                    <goals>
                        <goal>check</goal>
                    </goals>
                </execution>
            </executions>
        </plugin>

        <!-- SpotBugs Plugin -->
        <plugin>
            <groupId>com.github.spotbugs</groupId>
            <artifactId>spotbugs-maven-plugin</artifactId>
            <version>4.8.3.0</version>
            <configuration>
                <effort>Max</effort>
                <threshold>Low</threshold>
                <failOnError>true</failOnError>
            </configuration>
            <executions>
                <execution>
                    <goals>
                        <goal>check</goal>
                    </goals>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

### 2. Optional: Configure PMD Ruleset
Create `pmd-ruleset.xml` in your project root:

```xml
<?xml version="1.0"?>
<ruleset name="Custom Rules"
         xmlns="http://pmd.sourceforge.net/ruleset/2.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://pmd.sourceforge.net/ruleset/2.0.0 https://pmd.sourceforge.io/ruleset_2_0_0.xsd">
    <description>Custom PMD Ruleset</description>

    <rule ref="category/java/bestpractices.xml" />
    <rule ref="category/java/errorprone.xml" />
    <rule ref="category/java/codestyle.xml" />
</ruleset>
```

Then update the PMD plugin configuration:
```xml
<configuration>
    <rulesets>
        <ruleset>pmd-ruleset.xml</ruleset>
    </rulesets>
</configuration>
```

---

## Dockerfile Requirements

Ensure you have a `Dockerfile` in your repository root. See the example provided in this repository.

Key requirements:
- Multi-stage build for optimized image size
- Non-root user for security
- Proper JAR file placement
- Health check endpoint (optional but recommended)

---

## Branch Strategy

The pipeline is configured for the following branches:

| Branch | Environment | Deployment | Description |
|--------|-------------|------------|-------------|
| `develop` | Development | Auto-deploy on push | Active development branch |
| `staging` | Staging | Auto-deploy on push | Pre-production testing |
| `main` | Production | Manual (not configured) | Production-ready code |

### Workflow:
1. Developers push to `develop` → Auto-deploys to Development
2. QA testing in Development environment
3. Merge `develop` to `staging` → Auto-deploys to Staging
4. Final testing in Staging environment
5. Merge `staging` to `main` → Manual production deployment

---

## Security Scanning Thresholds

### OWASP Dependency-Check
- **Failure Threshold:** CVSS score ≥ 7.0
- **Scope:** Application dependencies and JAR files
- **Action on Failure:** Pipeline fails, manual review required

### Aqua Security Trivy
- **Failure Threshold:** CRITICAL or HIGH severity vulnerabilities
- **Scope:** Container image layers and OS packages
- **Action on Failure:** Pipeline fails, image is not pushed to GHCR

---

## Verification Steps

### 1. Test the Pipeline
```bash
# Push to develop branch
git checkout develop
git add .
git commit -m "test: trigger CI/CD pipeline"
git push origin develop
```

### 2. Monitor Pipeline Execution
1. Go to **Actions** tab in your repository
2. Click on the running workflow
3. Monitor each job's progress

### 3. Verify GHCR Image
```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Pull the image
docker pull ghcr.io/YOUR_ORG/YOUR_REPO:develop-COMMIT_SHA

# Run the container
docker run -p 8080:8080 ghcr.io/YOUR_ORG/YOUR_REPO:develop-COMMIT_SHA
```

---

## Troubleshooting

### Pipeline Fails at Build Stage
- **Issue:** Maven dependencies cannot be downloaded
- **Solution:** Check network connectivity and Maven Central accessibility

### Pipeline Fails at Quality Gate
- **Issue:** PMD or SpotBugs violations detected
- **Solution:** Review the uploaded reports in the Actions artifacts and fix code issues

### Pipeline Fails at Security Scan
- **Issue:** Critical vulnerabilities detected in dependencies or container
- **Solution:**
  1. Review OWASP Dependency-Check report
  2. Update vulnerable dependencies in `pom.xml`
  3. Review Trivy scan results
  4. Update base image in Dockerfile

### Deployment Webhook Fails
- **Issue:** Webhook returns 4xx or 5xx error
- **Solution:**
  1. Verify webhook URL is correct
  2. Check webhook service logs
  3. Ensure payload format matches expected schema

### GHCR Push Permission Denied
- **Issue:** Cannot push to GitHub Container Registry
- **Solution:**
  1. Verify **Workflow permissions** are set to "Read and write"
  2. Check if package already exists with restricted access
  3. Verify repository has Packages feature enabled

---

## Customization Options

### Adjust Security Scan Thresholds

#### OWASP Dependency-Check
Edit `.github/workflows/ci-cd-pipeline.yml`:
```yaml
args: >
  --scan target/*.jar
  --failOnCVSS 8  # Change from 7 to 8 for less strict
  --enableRetired
```

#### Trivy
```yaml
severity: 'CRITICAL'  # Remove HIGH to only fail on CRITICAL
exit-code: '1'
```

### Add Additional Environments
1. Create new environment in GitHub Settings
2. Add deployment job in workflow:
```yaml
deploy-production:
  name: Deploy to Production
  runs-on: ubuntu-latest
  needs: container-build-scan
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
  environment:
    name: production
    url: ${{ vars.PROD_URL }}
  # ... rest of deployment steps
```

### Change Notification Channel
Replace the Slack notification step with your preferred service:
- **Microsoft Teams:** Use `aliencube/microsoft-teams-actions@v0.8.0`
- **Discord:** Use `sarisia/actions-status-discord@v1`
- **Email:** Use `dawidd6/action-send-mail@v3`

---

## Maintenance

### Regular Updates
- Update action versions quarterly
- Review security scan results weekly
- Rotate webhook URLs annually
- Update base Docker images monthly

### Monitoring
- Set up alerts for pipeline failures
- Track deployment frequency
- Monitor container image sizes
- Review security scan trends

---

## Support

For issues or questions:
1. Check GitHub Actions logs in the **Actions** tab
2. Review artifact reports (PMD, SpotBugs, OWASP)
3. Consult GitHub Actions documentation: https://docs.github.com/actions
4. Check tool-specific documentation:
   - Maven PMD: https://maven.apache.org/plugins/maven-pmd-plugin/
   - SpotBugs: https://spotbugs.github.io/
   - OWASP Dependency-Check: https://owasp.org/www-project-dependency-check/
   - Trivy: https://aquasecurity.github.io/trivy/

---

## Quick Reference: All Secrets and Variables

### Secrets (Settings → Secrets and variables → Actions → Secrets)
- `GITHUB_TOKEN` - Auto-provided
- `SLACK_WEBHOOK_URL` - Optional
- `FAILURE_WEBHOOK_URL` - Optional
- `DEV_DEPLOY_WEBHOOK` - Required for dev deployment
- `STAGING_DEPLOY_WEBHOOK` - Required for staging deployment

### Variables (Settings → Secrets and variables → Actions → Variables)
- `DEV_URL` - Development environment URL
- `STAGING_URL` - Staging environment URL

### Workflow Permissions (Settings → Actions → General)
- ✅ Read and write permissions
- ✅ Allow GitHub Actions to create and approve pull requests
