# User Management Service - CI/CD Pipeline
## Service ID: SVC-001

Production-grade GitLab CI/CD pipeline for the User Management Service, a core service responsible for user authentication, authorization, profile management, and accessibility preferences in the medication management system.

---

## 📋 Overview

This repository contains a comprehensive GitLab CI/CD pipeline that automates:
- Building Spring Boot applications
- Running unit and integration tests
- Static code analysis (SonarCloud)
- Security scanning (Snyk, Trivy, OWASP Dependency Check)
- Docker image creation and registry push
- Deployment to Google Kubernetes Engine (GKE)
- Post-deployment smoke testing
- Failure notifications

---

## 🏗️ Architecture

**Technology Stack:**
- **Application Framework:** Spring Boot
- **Authentication:** OAuth 2.0/OpenID Connect, JWT
- **Database:** PostgreSQL
- **Cache:** Redis (session caching)
- **Message Bus:** Event Bus (Kafka/RabbitMQ)
- **Container Orchestration:** Google Kubernetes Engine (GKE)
- **CI/CD:** GitLab CI/CD

**Service Dependencies:**
1. PostgreSQL Database
2. Redis Cache
3. Event Bus

---

## 📁 Repository Structure

```
.
├── .gitlab-ci.yml                      # Main CI/CD pipeline configuration
├── Dockerfile                          # Multi-stage Docker build
├── dependency-check-suppression.xml    # OWASP suppression rules
├── CICD-SETUP-GUIDE.md                # Comprehensive setup documentation
├── GITLAB-VARIABLES-QUICK-REF.md      # Quick reference for CI/CD variables
├── README.md                          # This file
│
├── k8s/                               # Kubernetes manifests
│   ├── deployment.yaml                # Deployment configuration
│   ├── service.yaml                   # Service definitions
│   └── hpa.yaml                       # Horizontal Pod Autoscaler
│
├── src/                               # Application source code
│   ├── main/
│   │   ├── java/
│   │   └── resources/
│   └── test/
│
└── pom.xml                            # Maven project configuration
```

---

## 🚀 Quick Start

### Prerequisites

1. **GitLab Project Setup**
   - GitLab repository with admin access
   - GitLab Runner with Docker executor
   - Container Registry enabled

2. **External Services**
   - PostgreSQL database (accessible from CI/CD)
   - Redis cache instance
   - Event Bus (Kafka/RabbitMQ)
   - Google Kubernetes Engine cluster

3. **Third-Party Accounts**
   - SonarCloud account and project
   - Snyk account and organization
   - Slack workspace (for notifications)

### Step 1: Configure CI/CD Variables

See **[GITLAB-VARIABLES-QUICK-REF.md](GITLAB-VARIABLES-QUICK-REF.md)** for the complete checklist.

**Critical Variables (15 required):**
```bash
# Database
DB_HOST, DB_PORT, DB_NAME, DB_USERNAME, DB_PASSWORD

# Redis
REDIS_HOST, REDIS_PORT, REDIS_PASSWORD

# Security
JWT_SECRET, OAUTH_CLIENT_SECRET

# GKE
GKE_SERVICE_ACCOUNT_KEY, GCP_PROJECT_ID, GKE_CLUSTER_NAME, GKE_REGION

# Deployment
DEPLOYMENT_URL
```

Navigate to: **Settings > CI/CD > Variables** and add all required variables.

### Step 2: Set Up Kubernetes Manifests

Copy the Kubernetes manifests from the setup guide to your `k8s/` directory:
- `k8s/deployment.yaml`
- `k8s/service.yaml`
- `k8s/hpa.yaml`

Customize resource limits, replica counts, and environment-specific values.

### Step 3: Create Dockerfile

Use the provided multi-stage Dockerfile in the repository root. It's optimized for:
- Layered Spring Boot builds
- Minimal image size
- Non-root user execution
- Built-in health checks

### Step 4: Configure GKE Service Account

```bash
# Create service account
gcloud iam service-accounts create gitlab-ci-deployer \
  --display-name="GitLab CI Deployer"

# Grant permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

# Create key and encode
gcloud iam service-accounts keys create key.json \
  --iam-account=gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

cat key.json | base64 -w 0 > key.json.b64
```

Add the contents of `key.json.b64` to GitLab variable `GKE_SERVICE_ACCOUNT_KEY`.

### Step 5: Push to Repository

```bash
git add .
git commit -m "Add CI/CD pipeline configuration"
git push origin develop
```

The pipeline will automatically trigger!

---

## 🔄 Pipeline Stages

The pipeline consists of 9 stages:

### 1. **Validate** (2 jobs)
- `validate:dependencies` - Validates Maven project structure
- `validate:code-format` - Checks code formatting standards

### 2. **Build** (1 job)
- `build:compile` - Compiles Spring Boot application
- Caches `.m2/repository` for faster subsequent builds

### 3. **Test** (2 jobs)
- `test:unit` - Runs JUnit tests with JaCoCo coverage
- `test:integration` - Runs integration tests with Testcontainers
- Generates JUnit XML reports for GitLab visualization

### 4. **Analyze** (1 job)
- `analyze:sonarcloud` - Static code analysis and quality gates

### 5. **Security** (2 jobs)
- `security:snyk` - Dependency vulnerability scanning
- `security:dependency-check` - OWASP vulnerability analysis

### 6. **Package** (3 jobs)
- `package:jar` - Creates executable JAR artifact
- `package:docker` - Builds Docker image with multiple tags
- `security:trivy` - Container image vulnerability scan

**Image Tags:**
- `${CI_COMMIT_SHORT_SHA}` - Git commit SHA
- `${SERVICE_ID}-${BUILD_VERSION}` - Service ID + version (e.g., `SVC-001-1.2.3`)
- `${SERVICE_ID}-latest` - Latest build for the service

### 7. **Deploy** (2 jobs)
- `deploy:pre-check` - Verifies dependencies (PostgreSQL, Redis, Event Bus)
- `deploy:development` - Deploys to GKE development environment

**Pre-deployment checks ensure:**
- PostgreSQL is reachable
- Redis is accessible
- Event Bus connectivity (warning only)

### 8. **Smoke Test** (1 job)
- `smoke-test:api-health` - Tests all API endpoints:
  - `/actuator/health`
  - `/api/auth/register`
  - `/api/auth/login`
  - `/api/auth/refresh`
  - `/api/users`
  - `/api/users/{id}`
  - `/api/users/preferences`
  - `/api/users/emergency-access`

### 9. **Notify** (2 jobs)
- `notify:success` - Sends success notification to Slack
- `notify:failure` - Sends failure notification to Slack/Email

---

## 🔐 Security Features

### 1. **Secrets Management**
- All secrets stored as GitLab CI/CD variables
- Sensitive values marked as "Masked" in logs
- Secrets injected as Kubernetes secrets at deployment

### 2. **Multi-Layer Security Scanning**
- **SAST:** SonarCloud static analysis
- **SCA:** Snyk dependency scanning
- **Container Scanning:** Trivy image scanning
- **OWASP:** Dependency-Check for known CVEs

### 3. **Runtime Security**
- Non-root container user (UID 1001)
- Read-only root filesystem capability
- Resource limits enforced
- Network policies (recommended to add)

### 4. **Access Control**
- Protected branches for main/develop
- Manual approval for production deployments
- Audit logging enabled

---

## 📊 Monitoring & Observability

### Test Reports
- JUnit test results visible in GitLab Merge Requests
- Code coverage reports in SonarCloud
- Vulnerability reports in Snyk dashboard

### Health Checks
- Liveness probe: `/actuator/health/liveness`
- Readiness probe: `/actuator/health/readiness`
- Startup probe with 150s timeout

### Logs & Metrics
- Application logs: `kubectl logs -n development -l app=user-management-service`
- Metrics: Spring Boot Actuator metrics endpoint
- GKE monitoring: GCP Console

---

## 🎯 API Endpoints

The service exposes the following endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/auth/register` | POST | User registration |
| `/api/auth/login` | POST | User authentication |
| `/api/auth/refresh` | POST | JWT token refresh |
| `/api/users` | GET | List all users (authenticated) |
| `/api/users/{id}` | GET | Get user by ID (authenticated) |
| `/api/users/preferences` | GET/PUT | User accessibility preferences |
| `/api/users/emergency-access` | POST | Emergency access management |
| `/actuator/health` | GET | Health check endpoint |

---

## 🔧 Configuration

### Maven Settings

The pipeline uses these Maven configurations:
```bash
MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository"
MAVEN_CLI_OPTS: "--batch-mode --errors --fail-at-end --show-version"
```

### Spring Profiles

- **test:** Used for unit tests
- **integration-test:** Used for integration tests
- **development:** Deployed to dev environment
- **staging:** (Optional) Staging environment
- **production:** (Optional) Production environment

### Resource Allocation

**Development Environment:**
- Replicas: 3
- CPU Request: 250m
- CPU Limit: 1000m
- Memory Request: 512Mi
- Memory Limit: 2Gi

**Autoscaling:**
- Min Replicas: 3
- Max Replicas: 10
- CPU Threshold: 70%
- Memory Threshold: 80%

---

## 🐛 Troubleshooting

### Pipeline Fails at Build Stage

**Symptoms:** Maven compilation errors
**Solutions:**
1. Check Java version compatibility (requires JDK 17)
2. Verify `pom.xml` dependencies
3. Review Maven cache - may need to clear

### Database Connection Fails in Tests

**Symptoms:** Connection refused errors
**Solutions:**
1. Verify PostgreSQL service is running in `.gitlab-ci.yml`
2. Check `DATABASE_URL` environment variable
3. Ensure service alias matches hostname

### Deployment Fails - Pre-check Error

**Symptoms:** "PostgreSQL/Redis is not reachable"
**Solutions:**
1. Verify CI/CD variables are set correctly
2. Check network connectivity from GKE to databases
3. Validate database credentials
4. Check firewall rules

### Smoke Tests Fail

**Symptoms:** HTTP timeouts or connection errors
**Solutions:**
1. Increase sleep time in smoke test (default 30s)
2. Verify `DEPLOYMENT_URL` variable
3. Check LoadBalancer/Ingress configuration
4. Review pod status: `kubectl get pods -n development`

### Snyk/Trivy Fails Pipeline

**Symptoms:** Security scans find HIGH/CRITICAL vulnerabilities
**Solutions:**
1. Review vulnerability reports
2. Update dependencies to patched versions
3. Add suppressions to `dependency-check-suppression.xml` for false positives
4. Temporarily set `allow_failure: true` (not recommended for prod)

---

## 🚦 Branch Strategy

### Development (`develop` branch)
- Auto-deploys to development environment
- All security scans enabled
- Full test suite execution

### Main (`main` branch)
- Auto-deploys to development
- Can be configured for staging deployment
- Production deployment requires manual trigger

### Feature Branches
- Runs tests and security scans
- Does not deploy
- Creates merge request pipeline

### Tags (e.g., `v1.2.3`)
- Recommended for production releases
- Configure production deployment job to trigger on tags

---

## 📚 Additional Documentation

- **[CICD-SETUP-GUIDE.md](CICD-SETUP-GUIDE.md)** - Complete setup guide with detailed instructions
- **[GITLAB-VARIABLES-QUICK-REF.md](GITLAB-VARIABLES-QUICK-REF.md)** - Quick reference for CI/CD variables
- **[dependency-check-suppression.xml](dependency-check-suppression.xml)** - OWASP vulnerability suppressions

---

## 🤝 Contributing

### Before Submitting Code

1. Run tests locally:
   ```bash
   mvn clean verify
   ```

2. Check code formatting:
   ```bash
   mvn spotless:check
   ```

3. Ensure no security vulnerabilities:
   ```bash
   mvn org.owasp:dependency-check-maven:check
   ```

### Merge Request Checklist

- [ ] All tests pass
- [ ] Code coverage > 80%
- [ ] No critical security vulnerabilities
- [ ] Documentation updated
- [ ] Commit messages follow convention

---

## 📞 Support

**DevOps Team:**
- Email: devops-team@example.com
- Slack: #devops-support
- On-call: PagerDuty rotation

**Security Issues:**
- Report to: security@example.com
- Use GitLab confidential issues

---

## 📜 License

Proprietary - Internal Use Only

---

## 🎉 Acknowledgments

Built by the DevOps team for the Medication Management System project.

**Pipeline Version:** 1.0
**Last Updated:** 2026-01-12
**Service ID:** SVC-001
**Service Name:** User Management Service

---

## 🔄 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-12 | Initial production-grade pipeline |

---

**Ready to deploy?** Follow the [CICD-SETUP-GUIDE.md](CICD-SETUP-GUIDE.md) for step-by-step instructions!
