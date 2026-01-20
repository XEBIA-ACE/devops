# Production CI/CD Pipeline for Python/Maven Application

![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)
![Maven](https://img.shields.io/badge/Maven-C71A36?style=for-the-badge&logo=apache-maven&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Java](https://img.shields.io/badge/Java_17-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)

## Overview

A streamlined, production-ready CI/CD pipeline implementing automated build, quality gates, security scanning, and deployment to multiple environments using GitHub Actions.

---

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        TRIGGER EVENTS                           │
│  • Push to main/develop/staging   • Pull Request to branches   │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    STAGE 1: BUILD & TEST                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  • Checkout code                                         │  │
│  │  • Setup JDK 17 + Maven                                  │  │
│  │  • Cache Maven dependencies (~/.m2/repository)           │  │
│  │  • Build: mvn clean package -DskipTests                  │  │
│  │  • Test: mvn test                                        │  │
│  │  • Upload JAR artifacts (7-day retention)                │  │
│  └──────────────────────────────────────────────────────────┘  │
│  Time: 30-60 sec (cached) | 2-3 min (first run)                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   STAGE 2: QUALITY GATE                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  PMD Analysis                                            │  │
│  │  • Code quality checks                                   │  │
│  │  • failOnViolation=true                                  │  │
│  │  • Report: target/site/pmd.html                          │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  SpotBugs Analysis                                       │  │
│  │  • Bug pattern detection                                 │  │
│  │  • Effort=Max, Threshold=Low                             │  │
│  │  • FindSecBugs plugin enabled                            │  │
│  │  • Report: target/spotbugsXml.xml                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ❌ FAILS PIPELINE if violations detected                       │
│  Time: 30-45 sec (cached) | 1-2 min (first run)                │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              STAGE 3: CONTAINER BUILD & SCAN                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Docker Build                                            │  │
│  │  • Download JAR artifacts from Stage 1                   │  │
│  │  • Build multi-stage Dockerfile                          │  │
│  │  • Base: eclipse-temurin:17-jre-alpine                   │  │
│  │  • Non-root user (UID 1001)                              │  │
│  │  • Cache Docker layers (GitHub Actions cache)            │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  OWASP Dependency-Check                                  │  │
│  │  • Scan JAR dependencies                                 │  │
│  │  • Fail on CVSS ≥ 7.0                                    │  │
│  │  • Output: HTML/XML/JSON reports                         │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  Aqua Security Trivy                                     │  │
│  │  • Scan container image                                  │  │
│  │  • Severity: CRITICAL, HIGH                              │  │
│  │  • SARIF output → GitHub Security tab                    │  │
│  │  • Exit code 1 on vulnerabilities                        │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  Push to GHCR                                            │  │
│  │  • Registry: ghcr.io                                     │  │
│  │  • Tags: branch-SHA, branch, latest                      │  │
│  │  • Only pushes if scans pass ✅                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│  Time: 1-2 min (cached) | 3-5 min (first run)                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ├─────────────┬─────────────┐
                         ▼             ▼             ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  DEPLOY: DEV     │ │  DEPLOY: STAGING │ │  NOTIFY: FAIL    │
├──────────────────┤ ├──────────────────┤ ├──────────────────┤
│ Trigger:         │ │ Trigger:         │ │ Trigger:         │
│ • develop push   │ │ • staging push   │ │ • Any job fails  │
│                  │ │                  │ │                  │
│ Environment:     │ │ Environment:     │ │ Channels:        │
│ • development    │ │ • staging        │ │ • Slack          │
│ • DEV_URL        │ │ • STAGING_URL    │ │ • Generic        │
│                  │ │                  │ │   Webhook        │
│ Webhook:         │ │ Webhook:         │ │                  │
│ • POST image     │ │ • POST image     │ │ Payload:         │
│ • Deploy script  │ │ • Deploy script  │ │ • Repo info      │
│                  │ │                  │ │ • Commit SHA     │
│ Protection:      │ │ Protection:      │ │ • Run URL        │
│ • None (auto)    │ │ • Reviewers      │ │ • Author         │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

---

## Key Features

### 🚀 Optimized Build
- **Aggressive Caching**: Maven dependencies cached using pom.xml hash
- **Layer Caching**: Docker BuildKit with GitHub Actions cache backend
- **Fast Rebuilds**: 30-60 seconds for cached builds vs 2-3 minutes cold

### 🛡️ Security Hardening
- **Multi-layer Scanning**: OWASP + Trivy for comprehensive coverage
- **Non-root Containers**: Application runs as UID 1001
- **Minimal Base Image**: Alpine Linux for reduced attack surface
- **SARIF Integration**: Security findings in GitHub Security tab

### ✅ Quality Enforcement
- **PMD**: Code quality and style violations (fails on issues)
- **SpotBugs**: Bug pattern detection with FindSecBugs plugin
- **Fail-Fast**: Pipeline stops immediately on quality violations

### 📦 Container Registry
- **GHCR Integration**: Native GitHub Container Registry support
- **Smart Tagging**: SHA-based tags + branch tags + latest
- **Automatic Cleanup**: Old images can be pruned via retention policies

### 🎯 Linear Deployment
- **Push-to-Deploy**: Direct deployment on branch push
- **Environment Tracking**: Native GitHub Environments for history
- **Webhook-based**: Flexible integration with any deployment system

### 🔔 Smart Notifications
- **Failure-Only**: Only notifies on pipeline failures
- **Multiple Channels**: Slack + generic webhook support
- **Rich Context**: Full pipeline details in notifications

---

## Quick Start

### 1. Prerequisites
```bash
# Verify you have these files
.github/workflows/ci-cd-pipeline.yml  ✅
Dockerfile.maven                      ✅
pom.xml                               ✅
```

### 2. Configure GitHub (5 minutes)

**Add Secrets** (Settings → Secrets and variables → Actions):
```
GITHUB_TOKEN                 # Auto-provided ✅
DEV_DEPLOY_WEBHOOK          # Your dev deployment endpoint
STAGING_DEPLOY_WEBHOOK      # Your staging deployment endpoint
SLACK_WEBHOOK_URL           # Optional: Slack notifications
```

**Add Variables** (Settings → Secrets and variables → Actions → Variables):
```
DEV_URL                     # https://dev.yourapp.com
STAGING_URL                 # https://staging.yourapp.com
```

**Set Permissions** (Settings → Actions → General):
```
☑️ Read and write permissions
☑️ Allow GitHub Actions to create and approve pull requests
```

**Create Environments** (Settings → Environments):
```
• development (branch: develop, no protection)
• staging (branch: staging, require reviewers)
```

### 3. Test the Pipeline
```bash
git checkout develop
echo "# Test CI/CD" >> README.md
git add README.md
git commit -m "test: trigger pipeline"
git push origin develop
```

### 4. Monitor Execution
1. Go to **Actions** tab
2. Click on running workflow
3. Watch each stage complete
4. Check **Packages** for Docker image
5. Verify deployment in **Environments** section

---

## Pipeline Stages Explained

### Stage 1: Build & Test
**Purpose**: Compile application and verify unit tests pass

**Steps**:
1. Checkout code from git
2. Setup Java 17 (Eclipse Temurin)
3. Restore Maven cache or download dependencies
4. Run `mvn clean package -DskipTests` (build only)
5. Run `mvn test` (separate test execution)
6. Upload JAR artifacts for downstream jobs

**Caching Strategy**:
```yaml
cache-key: linux-maven-<pom.xml-hash>
cache-path: ~/.m2/repository
invalidation: When pom.xml changes
```

**Output**: JAR files in `target/` directory

---

### Stage 2: Quality Gate
**Purpose**: Enforce code quality standards and detect bugs

**PMD Analysis**:
- Checks: Best practices, error-prone patterns, code style
- Ruleset: Default Maven PMD ruleset
- Failure: Pipeline fails if violations found
- Report: HTML report uploaded as artifact

**SpotBugs Analysis**:
- Checks: 400+ bug patterns
- Effort: Maximum (thorough analysis)
- Threshold: Low (catch all issues)
- Security: FindSecBugs plugin for security issues
- Failure: Pipeline fails if bugs found
- Report: XML report uploaded as artifact

**Why This Matters**: Prevents buggy or low-quality code from reaching production

---

### Stage 3: Container Build & Scan
**Purpose**: Build hardened Docker image and scan for vulnerabilities

**Docker Build**:
- Base image: `eclipse-temurin:17-jre-alpine` (minimal, secure)
- Multi-stage: Build stage + runtime stage
- Security: Non-root user, minimal packages
- Optimization: JVM container support, G1GC
- Caching: GitHub Actions cache for fast rebuilds

**OWASP Dependency-Check**:
- Scans: Application dependencies in JAR files
- Database: National Vulnerability Database (NVD)
- Threshold: CVSS score ≥ 7.0 (HIGH/CRITICAL)
- Output: HTML/XML/JSON reports
- Action: Fails pipeline on high-severity vulnerabilities

**Aqua Security Trivy**:
- Scans: Container image layers, OS packages, app dependencies
- Severity: CRITICAL and HIGH only
- Format: SARIF (GitHub Security) + Table (logs)
- Integration: Findings appear in Security tab
- Action: Fails pipeline on critical/high vulnerabilities

**Push to GHCR**:
- Only if all scans pass ✅
- Tags: `develop-abc123f`, `develop`, `latest` (on main)
- Immutable: SHA-based tags never overwritten
- Credentials: Uses `GITHUB_TOKEN` automatically

---

### Stage 4: Deployment (Development)
**Trigger**: Push to `develop` branch

**Process**:
1. Pipeline sends POST request to `DEV_DEPLOY_WEBHOOK`
2. Payload includes: image tag, commit SHA, branch, actor
3. Your deployment system receives webhook
4. Deployment system pulls image from GHCR
5. Deployment system updates development environment

**Example Webhook Payload**:
```json
{
  "environment": "development",
  "image": "ghcr.io/yourorg/yourrepo:develop-abc123f",
  "commit": "abc123f",
  "branch": "develop",
  "actor": "john.doe"
}
```

**GitHub Environment**: Tracks deployment history and status

---

### Stage 5: Deployment (Staging)
**Trigger**: Push to `staging` branch

**Same as Development** but with optional protection rules:
- Require approvals from team leads
- Optional wait timer before deployment
- More controlled deployment process

**Best Practice**: Merge `develop` → `staging` after QA approval

---

### Stage 6: Failure Notification
**Trigger**: Any pipeline job fails

**Slack Notification** (if configured):
```
🚨 Pipeline Failure Alert

Repository: yourorg/yourrepo
Branch: develop
Commit: abc123f
Author: john.doe

[View Pipeline] (clickable button)
```

**Generic Webhook** (if configured):
```json
{
  "status": "failure",
  "repository": "yourorg/yourrepo",
  "branch": "develop",
  "commit": "abc123f",
  "author": "john.doe",
  "workflow": "CI/CD Pipeline",
  "run_url": "https://github.com/yourorg/yourrepo/actions/runs/12345"
}
```

**Smart Behavior**: Only fires on failures, not on success

---

## Image Tagging Strategy

### Tag Format
```
ghcr.io/[ORG]/[REPO]:[TAG]
```

### Tag Types

| Tag Type | Example | When Applied | Purpose |
|----------|---------|--------------|---------|
| Branch + SHA | `develop-abc123f` | Always | Immutable, unique identifier |
| Branch | `develop` | Always | Latest for branch |
| Latest | `latest` | Only on `main` | Latest production image |
| Semver | `v1.2.3` | Manual tag push | Release versioning |

### Example
```bash
# After pushing to develop branch (SHA: abc123f)
ghcr.io/yourorg/yourrepo:develop-abc123f  # Immutable
ghcr.io/yourorg/yourrepo:develop          # Mutable (latest for develop)

# After pushing to main branch (SHA: xyz789a)
ghcr.io/yourorg/yourrepo:main-xyz789a     # Immutable
ghcr.io/yourorg/yourrepo:main             # Mutable (latest for main)
ghcr.io/yourorg/yourrepo:latest           # Mutable (latest production)
```

### Best Practices
- **Deploy with SHA tags**: `develop-abc123f` for rollback capability
- **Use latest for quick testing**: `develop` for rapid iteration
- **Production uses semver**: `v1.2.3` for version control

---

## Branch Strategy

### Recommended Workflow

```
feature/xyz → develop → staging → main
              (auto)    (auto)   (manual)
                ↓         ↓         ↓
               DEV     STAGING   PRODUCTION
```

### Branch Policies

| Branch | Protection | Deployments | Description |
|--------|-----------|-------------|-------------|
| `develop` | Basic | Development (auto) | Active development |
| `staging` | Require PR | Staging (auto) | Pre-production testing |
| `main` | Require PR + Reviews | Manual | Production-ready code |
| `feature/*` | None | None | Feature branches |

### Development Flow

1. **Feature Development**
   ```bash
   git checkout -b feature/new-feature
   # Make changes
   git push origin feature/new-feature
   # Create PR to develop
   ```

2. **Development Testing**
   ```bash
   # After PR merge to develop
   # Pipeline auto-deploys to Development
   # QA tests in dev environment
   ```

3. **Staging Preparation**
   ```bash
   git checkout staging
   git merge develop
   git push origin staging
   # Pipeline auto-deploys to Staging
   # Final testing and approval
   ```

4. **Production Release**
   ```bash
   git checkout main
   git merge staging
   git tag v1.2.3
   git push origin main --tags
   # Manual production deployment
   ```

---

## Performance Benchmarks

### First Run (No Cache)
```
Build & Test:           2-3 minutes
Quality Gate:           1-2 minutes
Container Build & Scan: 3-5 minutes
Deployment:             10-30 seconds
Total:                  7-10 minutes
```

### Subsequent Runs (Cached)
```
Build & Test:           30-60 seconds
Quality Gate:           30-45 seconds
Container Build & Scan: 1-2 minutes
Deployment:             10-30 seconds
Total:                  2-4 minutes
```

### Optimization Tips
1. **Cache Hit Rate**: Keep pom.xml stable
2. **Layer Caching**: Order Dockerfile commands efficiently
3. **Parallel Jobs**: Jobs run in parallel when possible
4. **Artifact Size**: Keep JAR files minimal

---

## Security Features

### Container Security
- ✅ Non-root user (UID 1001, GID 1001)
- ✅ Minimal base image (Alpine Linux)
- ✅ Security updates applied
- ✅ No unnecessary packages
- ✅ Read-only file system compatible

### Dependency Security
- ✅ OWASP NVD database scanning
- ✅ CVSS score thresholds
- ✅ Automated vulnerability alerts
- ✅ Transitive dependency checking

### Image Security
- ✅ Multi-layer vulnerability scanning
- ✅ OS package vulnerability detection
- ✅ Configuration security checks
- ✅ SARIF integration for tracking

### Pipeline Security
- ✅ Secrets managed via GitHub Secrets
- ✅ Least-privilege GITHUB_TOKEN
- ✅ Signed container images (optional)
- ✅ Environment protection rules

---

## Troubleshooting Guide

### Build Failures

**Symptom**: Maven build fails
```
Error: Cannot resolve dependencies
```
**Solution**:
1. Check Maven Central status
2. Verify pom.xml syntax
3. Clear cache and retry: Re-run workflow

---

**Symptom**: Tests fail
```
Error: 3 tests failed
```
**Solution**:
1. Download test reports from artifacts
2. Fix failing tests locally
3. Re-run `mvn test` before pushing

---

### Quality Gate Failures

**Symptom**: PMD violations
```
Error: 15 PMD violations found
```
**Solution**:
1. Download PMD report from artifacts
2. Review violations: Navigate to line numbers
3. Fix code issues or adjust ruleset
4. Re-run locally: `mvn pmd:check`

---

**Symptom**: SpotBugs issues
```
Error: 5 bugs found
```
**Solution**:
1. Download SpotBugs report from artifacts
2. Review bug patterns
3. Fix security issues (FindSecBugs)
4. Re-run locally: `mvn spotbugs:check`

---

### Security Scan Failures

**Symptom**: OWASP high CVSS
```
Error: Dependency has CVSS 8.5
```
**Solution**:
1. Download dependency-check report
2. Identify vulnerable dependency
3. Update version in pom.xml
4. If no update available: Request CVE override or accept risk

---

**Symptom**: Trivy critical vulnerability
```
Error: CRITICAL vulnerability in base image
```
**Solution**:
1. Check Trivy report in Security tab
2. Update base image tag in Dockerfile
3. Consider distroless images
4. Verify vulnerability is exploitable in your context

---

### Deployment Failures

**Symptom**: Webhook 500 error
```
Error: POST to webhook failed with 500
```
**Solution**:
1. Check webhook service logs
2. Verify webhook endpoint is accessible
3. Test webhook manually with curl
4. Verify payload format matches expected schema

---

**Symptom**: Image pull failure
```
Error: Cannot pull image from GHCR
```
**Solution**:
1. Verify image exists: Check Packages section
2. Check image visibility: Must be accessible
3. Verify credentials: Use GITHUB_TOKEN
4. Check package permissions

---

### Permission Issues

**Symptom**: Cannot push to GHCR
```
Error: denied: permission_denied
```
**Solution**:
1. Settings → Actions → General → Workflow permissions
2. Select "Read and write permissions"
3. Save and re-run workflow

---

## Customization Examples

### Add Code Coverage

```yaml
- name: Generate code coverage
  run: mvn jacoco:report

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    files: ./target/site/jacoco/jacoco.xml
```

### Add SonarQube

```yaml
- name: SonarQube scan
  run: |
    mvn sonar:sonar \
      -Dsonar.projectKey=${{ github.repository }} \
      -Dsonar.host.url=${{ secrets.SONAR_HOST_URL }} \
      -Dsonar.login=${{ secrets.SONAR_TOKEN }}
```

### Add Production Deployment

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
    - name: Deploy to Production
      run: |
        curl -X POST "${{ secrets.PROD_DEPLOY_WEBHOOK }}" \
          -H "Content-Type: application/json" \
          -d '{
            "environment": "production",
            "image": "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:main-${{ github.sha }}"
          }'
```

### Add Smoke Tests

```yaml
- name: Run smoke tests
  run: |
    # Wait for deployment
    sleep 30

    # Test health endpoint
    curl -f ${{ vars.DEV_URL }}/actuator/health || exit 1

    # Test main endpoint
    curl -f ${{ vars.DEV_URL }}/api/status || exit 1
```

---

## Documentation Files

| File | Purpose |
|------|---------|
| `.github/workflows/ci-cd-pipeline.yml` | Main pipeline configuration |
| `PRODUCTION_CICD_SUMMARY.md` | Comprehensive pipeline documentation |
| `SECRETS_VARIABLES_CHECKLIST.md` | Setup checklist for secrets/variables |
| `GITHUB_ACTIONS_SETUP.md` | Detailed setup instructions |
| `README_PIPELINE.md` | This file - pipeline overview |
| `Dockerfile.maven` | Production Docker image |
| `pom.xml` | Maven configuration with plugins |

---

## Support & Resources

### Official Documentation
- [GitHub Actions](https://docs.github.com/actions)
- [Maven PMD](https://maven.apache.org/plugins/maven-pmd-plugin/)
- [SpotBugs](https://spotbugs.github.io/)
- [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/)
- [Aqua Trivy](https://aquasecurity.github.io/trivy/)
- [GHCR](https://docs.github.com/packages)

### Community
- [GitHub Actions Marketplace](https://github.com/marketplace?type=actions)
- [Maven Central](https://search.maven.org/)
- [Docker Hub](https://hub.docker.com/)

---

## License

This CI/CD pipeline configuration is provided as-is for production use. Customize as needed for your specific requirements.

---

**Version**: 1.0.0
**Last Updated**: 2026-01-20
**Compatibility**: GitHub Actions, Maven 3.8+, Java 17+, Docker 20+
