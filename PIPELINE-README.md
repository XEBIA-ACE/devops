# GitLab CI/CD Pipeline for Node.js Express API

## 📋 Overview

This repository contains a production-ready, enterprise-grade GitLab CI/CD pipeline for Node.js Express API applications. The pipeline implements industry best practices for continuous integration, security scanning, and automated deployment to Google Kubernetes Engine (GKE).

---

## 🚀 Features

### Pipeline Capabilities

✅ **Automated Build & Test**
- Clean dependency installation with npm caching
- Unit and integration tests with PostgreSQL and Redis
- Code coverage reporting with JUnit XML output

✅ **Static Code Analysis**
- ESLint for code quality and style
- Prettier for code formatting
- SonarCloud for comprehensive code analysis

✅ **Security Scanning**
- Snyk for dependency vulnerability scanning
- Trivy for filesystem and container image scanning
- NPM audit for known vulnerabilities
- Secret detection in code

✅ **Container Packaging**
- Multi-stage Docker builds for optimal image size
- Security-hardened containers with non-root users
- Automated image tagging and registry push
- Container vulnerability scanning

✅ **Automated Deployment**
- Zero-downtime rolling deployments to GKE
- Separate staging and production environments
- Automated secret and config management
- Health checks and rollout verification

✅ **Observability & Notifications**
- Smoke tests after deployment
- Slack and Microsoft Teams notifications
- Comprehensive logging throughout pipeline
- Artifact retention for debugging

---

## 📁 Repository Structure

```
.
├── .gitlab-ci.yml              # Main CI/CD pipeline configuration
├── CICD-VARIABLES-GUIDE.md     # Comprehensive variables setup guide
├── PIPELINE-README.md          # This file
├── Dockerfile                  # Multi-stage production Dockerfile
├── .dockerignore              # Docker build context exclusions
├── k8s/                       # Kubernetes manifests
│   ├── deployment.yaml        # Deployment configuration
│   ├── service.yaml           # Service definition
│   ├── ingress.yaml           # Ingress routing rules
│   ├── hpa.yaml               # Horizontal Pod Autoscaler
│   └── serviceaccount.yaml    # RBAC configuration
├── src/                       # Application source code
├── tests/                     # Test files
└── package.json               # Node.js dependencies
```

---

## 🔧 Prerequisites

### Required Tools & Services

1. **GitLab Account**
   - GitLab.com or self-hosted instance
   - Container Registry enabled

2. **Google Cloud Platform (GCP)**
   - Active GCP project
   - GKE cluster created
   - Service account with deployment permissions

3. **Third-Party Services**
   - SonarCloud account (for code quality)
   - Snyk account (for security scanning)

4. **Infrastructure**
   - PostgreSQL database (staging & production)
   - Redis cache (staging & production)
   - Kubernetes cluster (GKE)

### Local Development Requirements

- Node.js 18+
- npm 9+
- Docker 24+
- kubectl (for manual K8s operations)

---

## ⚙️ Setup Instructions

### Step 1: Configure GitLab CI/CD Variables

Follow the comprehensive guide in `CICD-VARIABLES-GUIDE.md` to configure all required variables:

**Critical Variables:**
- `GCP_SERVICE_ACCOUNT_KEY`
- `GCP_PROJECT_ID`
- `GKE_CLUSTER`
- `GKE_ZONE`
- `SONAR_TOKEN`
- `SNYK_TOKEN`
- Database and Redis URLs
- JWT secrets and API keys

### Step 2: Prepare Your Application

Ensure your `package.json` includes the required scripts:

```json
{
  "scripts": {
    "start": "node src/index.js",
    "build": "tsc" or your build command,
    "test": "jest",
    "test:unit": "jest --testPathPattern=unit",
    "test:integration": "jest --testPathPattern=integration",
    "lint": "eslint src/**/*.js"
  }
}
```

### Step 3: Customize Configuration

1. **Update Application Name**
   - Edit `APP_NAME` in `.gitlab-ci.yml`
   - Update references in Kubernetes manifests

2. **Adjust Resource Limits**
   - Modify CPU/memory in `k8s/deployment.yaml`
   - Update HPA thresholds in `k8s/hpa.yaml`

3. **Configure Domain Names**
   - Update `ENVIRONMENT_URL` in workflow rules
   - Modify ingress hosts in `k8s/ingress.yaml`

### Step 4: Deploy Infrastructure

Before running the pipeline, ensure:

1. **GKE Cluster is ready**
   ```bash
   gcloud container clusters create production-cluster \
     --zone us-central1-a \
     --num-nodes 3 \
     --machine-type n1-standard-2
   ```

2. **Databases are accessible**
   - PostgreSQL with connection strings
   - Redis with connection strings

3. **Ingress Controller is installed**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
   ```

---

## 🔄 Pipeline Workflow

### Trigger Conditions

The pipeline runs automatically on:
- **Merge Requests** → Deploys to staging (manual)
- **Main Branch** → Deploys to production (manual)
- **Tags** → Production release build

### Pipeline Stages

#### 1️⃣ Build Stage (2-5 minutes)
- Installs npm dependencies with caching
- Runs build script (if available)
- Generates build metadata

#### 2️⃣ Test Stage (5-10 minutes)
- **Unit Tests**: Runs with coverage reporting
- **Integration Tests**: Tests with PostgreSQL and Redis
- Generates JUnit XML and Cobertura reports

#### 3️⃣ Static Analysis Stage (3-7 minutes)
- **ESLint**: Code quality and style checks
- **Prettier**: Code formatting verification
- **SonarCloud**: Comprehensive code analysis with quality gates

#### 4️⃣ Security Stage (5-10 minutes)
- **Snyk**: Dependency vulnerability scanning
- **Trivy**: Filesystem security scan
- **NPM Audit**: Known vulnerability check
- **Secret Detection**: Pattern-based secret scanning

#### 5️⃣ Package Stage (5-15 minutes)
- Builds multi-stage Docker image
- Scans container with Trivy
- Pushes to GitLab Container Registry
- Tags: `commit-sha`, `branch-name`, `latest`

#### 6️⃣ Deploy Stage (Manual - 5-10 minutes)
- Authenticates with GCP
- Creates/updates Kubernetes secrets and configs
- Deploys to GKE with rolling update
- Waits for rollout completion
- Verifies deployment health

#### 7️⃣ Post-Deploy Stage (1-3 minutes)
- Runs smoke tests against deployed API
- Verifies health endpoints
- Tests key API endpoints

#### 8️⃣ Notifications (Always runs)
- Sends success/failure notifications to Slack/Teams
- Includes pipeline metadata and links

---

## 🎯 Usage Examples

### Running the Full Pipeline

1. **Create a feature branch**
   ```bash
   git checkout -b feature/new-feature
   git push origin feature/new-feature
   ```

2. **Create a merge request**
   - Pipeline runs automatically
   - Manual staging deployment available

3. **Merge to main**
   ```bash
   git checkout main
   git merge feature/new-feature
   git push origin main
   ```

4. **Manual production deployment**
   - Navigate to CI/CD → Pipelines
   - Find the main branch pipeline
   - Click "Deploy to Production"

### Manual Pipeline Execution

```bash
# Trigger pipeline for current branch
git commit --allow-empty -m "trigger: pipeline"
git push
```

### Rollback Deployment

```bash
# Get previous deployment revision
kubectl rollout history deployment/express-api -n production

# Rollback to previous version
kubectl rollout undo deployment/express-api -n production

# Rollback to specific revision
kubectl rollout undo deployment/express-api -n production --to-revision=2
```

---

## 🔒 Security Features

### Container Security
- ✅ Non-root user (UID 1001)
- ✅ Read-only root filesystem capability
- ✅ Dropped all capabilities
- ✅ Security context constraints
- ✅ Minimal Alpine-based images

### Kubernetes Security
- ✅ Service account with RBAC
- ✅ Network policies (add as needed)
- ✅ Pod security policies
- ✅ Secret management via K8s secrets
- ✅ TLS/SSL termination at ingress

### Pipeline Security
- ✅ Masked sensitive variables
- ✅ Protected production variables
- ✅ No hardcoded secrets
- ✅ Automated security scanning
- ✅ Base64-encoded service account keys

---

## 🐛 Troubleshooting

### Common Issues

#### Issue: Pipeline fails at dependency installation
**Cause**: Cache corruption or network issues
**Solution**:
```yaml
# Clear cache in GitLab UI: CI/CD → Pipelines → Clear Runner Caches
# Or run:
npm cache clean --force
```

#### Issue: Tests fail with database connection errors
**Cause**: PostgreSQL service not ready
**Solution**: Increase wait time in `before_script`:
```bash
until pg_isready -h postgres -U test_user; do sleep 2; done
```

#### Issue: Docker build fails with authentication error
**Cause**: GitLab Container Registry not accessible
**Solution**:
1. Verify Container Registry is enabled
2. Check `CI_REGISTRY_*` variables are available
3. Ensure runner has internet access

#### Issue: GKE deployment fails with authentication error
**Cause**: Invalid or expired service account key
**Solution**:
1. Generate new GCP service account key
2. Base64 encode it correctly
3. Update `GCP_SERVICE_ACCOUNT_KEY` variable

#### Issue: Secrets not found in deployed pods
**Cause**: Secrets not created or wrong namespace
**Solution**:
```bash
# Verify secrets exist
kubectl get secrets -n production

# Check secret content
kubectl describe secret express-api-secrets -n production
```

### Debug Commands

```bash
# View pipeline logs
# Go to: CI/CD → Pipelines → Click on pipeline → Click on failed job

# Check pod logs
kubectl logs -f deployment/express-api -n production

# Get pod status
kubectl get pods -n production -l app=express-api

# Describe pod for events
kubectl describe pod <pod-name> -n production

# Check ingress status
kubectl get ingress -n production
kubectl describe ingress express-api -n production
```

---

## 📊 Monitoring & Observability

### GitLab Metrics

- **Pipeline Duration**: Track in GitLab → CI/CD → Analytics
- **Success Rate**: Monitor pipeline failure trends
- **Coverage Reports**: View in merge request widgets
- **Code Quality**: SonarCloud badges and reports

### Kubernetes Metrics

```bash
# CPU and memory usage
kubectl top pods -n production

# HPA status
kubectl get hpa -n production

# Deployment status
kubectl rollout status deployment/express-api -n production
```

### Application Logs

```bash
# Stream application logs
kubectl logs -f deployment/express-api -n production --tail=100

# Logs from all replicas
kubectl logs -l app=express-api -n production --tail=50
```

---

## 🔄 Continuous Improvement

### Performance Optimization

1. **Enable BuildKit for Docker**
   ```yaml
   variables:
     DOCKER_BUILDKIT: 1
   ```

2. **Parallelize Tests**
   ```yaml
   script:
     - npm test -- --maxWorkers=4
   ```

3. **Reduce Image Size**
   - Use `.dockerignore` effectively
   - Multi-stage builds (already implemented)
   - Alpine-based images (already implemented)

### Pipeline Enhancements

Consider adding:
- **E2E Tests**: Cypress, Playwright
- **Load Testing**: k6, Artillery
- **API Documentation**: Swagger/OpenAPI generation
- **Dependency Updates**: Renovate bot
- **Changelog Generation**: Automated release notes

---

## 📚 Additional Resources

### Documentation
- [GitLab CI/CD Docs](https://docs.gitlab.com/ee/ci/)
- [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/docs)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

### Tools
- [SonarCloud](https://sonarcloud.io/)
- [Snyk](https://snyk.io/)
- [Trivy](https://aquasecurity.github.io/trivy/)

---

## 🤝 Contributing

When contributing to this pipeline:

1. Test changes in a feature branch first
2. Update documentation for any configuration changes
3. Follow GitLab CI/CD YAML best practices
4. Ensure backward compatibility
5. Update CHANGELOG.md

---

## 📄 License

This pipeline configuration is provided as-is under the MIT License.

---

## 👥 Support

For issues or questions:

1. Check this README and `CICD-VARIABLES-GUIDE.md`
2. Review GitLab CI/CD job logs
3. Consult service-specific documentation
4. Contact DevOps team: devops@company.com

---

**Pipeline Version**: 1.0.0
**Last Updated**: 2026-01-12
**Maintained By**: DevOps Team
