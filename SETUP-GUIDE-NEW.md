# GitLab CI/CD Setup Guide
## User Management Service (SVC-001)

---

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [GitLab CI/CD Variables Configuration](#gitlab-cicd-variables-configuration)
4. [Third-Party Service Setup](#third-party-service-setup)
5. [Kubernetes Resources Setup](#kubernetes-resources-setup)
6. [Dockerfile Requirements](#dockerfile-requirements)
7. [Kubernetes Manifests](#kubernetes-manifests)
8. [Verification & Testing](#verification--testing)
9. [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides complete setup instructions for the GitLab CI/CD pipeline for the **User Management Service (SVC-001)**. The pipeline includes:

- ✅ Maven build with dependency caching
- ✅ Unit & Integration tests with PostgreSQL and Redis
- ✅ SonarCloud static analysis
- ✅ Snyk & Trivy security scanning
- ✅ Docker image building with multi-tagging (commit SHA + service ID)
- ✅ GKE deployment with pre-deployment dependency checks
- ✅ Comprehensive smoke tests for all API endpoints
- ✅ Slack notifications on success/failure

---

## Prerequisites

### 1. GitLab Project Setup
- GitLab project with Container Registry enabled
- GitLab Runner configured with Docker executor
- Runner tags: `docker`, `privileged` (for Docker builds)

### 2. External Services
- **Google Cloud Platform (GCP)** account with GKE cluster
- **SonarCloud** account and project
- **Snyk** account and organization
- **Slack** workspace (for notifications)

### 3. Infrastructure Dependencies
- PostgreSQL 15+ database instance
- Redis 7+ cache instance
- Event Bus (Kafka/RabbitMQ/AWS SNS)

---

## GitLab CI/CD Variables Configuration

Navigate to: **Settings → CI/CD → Variables** in your GitLab project and add the following variables:

### 🔐 Security Variables (Protected, Masked)

| Variable Name | Type | Description | Example Value | Protected | Masked |
|--------------|------|-------------|---------------|-----------|--------|
| `GKE_SERVICE_ACCOUNT_KEY` | Variable | Base64-encoded GCP service account JSON key | `eyJhbGc...` | ✅ | ✅ |
| `DB_PASSWORD` | Variable | PostgreSQL database password | `Str0ngP@ssw0rd!` | ✅ | ✅ |
| `REDIS_PASSWORD` | Variable | Redis cache password/auth token | `redis_secret_key` | ✅ | ✅ |
| `JWT_SECRET` | Variable | Secret key for JWT token signing | `your-256-bit-secret` | ✅ | ✅ |
| `OAUTH_CLIENT_SECRET` | Variable | OAuth 2.0 client secret | `oauth_client_secret` | ✅ | ✅ |
| `EVENT_BUS_PASSWORD` | Variable | Event bus authentication password | `eventbus_pwd` | ✅ | ✅ |
| `EVENT_BUS_USERNAME` | Variable | Event bus authentication username | `eventbus_user` | ✅ | ❌ |
| `SNYK_TOKEN` | Variable | Snyk authentication token | `snyk_token_here` | ✅ | ✅ |
| `SONAR_TOKEN` | Variable | SonarCloud authentication token | `sonar_token_here` | ✅ | ✅ |
| `SLACK_WEBHOOK_URL` | Variable | Slack incoming webhook URL | `https://hooks.slack.com/...` | ✅ | ✅ |

### 🌐 Configuration Variables (Protected, Not Masked)

| Variable Name | Type | Description | Example Value | Protected | Masked |
|--------------|------|-------------|---------------|-----------|--------|
| `GCP_PROJECT_ID` | Variable | Google Cloud project ID | `my-gcp-project-123456` | ✅ | ❌ |
| `GKE_CLUSTER_NAME` | Variable | GKE cluster name | `production-gke-cluster` | ✅ | ❌ |
| `GKE_REGION` | Variable | GKE cluster region | `us-central1` | ✅ | ❌ |
| `DB_HOST` | Variable | PostgreSQL database hostname | `postgres.example.com` | ✅ | ❌ |
| `DB_PORT` | Variable | PostgreSQL database port | `5432` | ✅ | ❌ |
| `DB_NAME` | Variable | PostgreSQL database name | `userservice_db` | ✅ | ❌ |
| `DB_USERNAME` | Variable | PostgreSQL database username | `userservice_app` | ✅ | ❌ |
| `REDIS_HOST` | Variable | Redis cache hostname | `redis.example.com` | ✅ | ❌ |
| `REDIS_PORT` | Variable | Redis cache port | `6379` | ✅ | ❌ |
| `EVENT_BUS_HOST` | Variable | Event bus hostname | `kafka.example.com` | ✅ | ❌ |
| `EVENT_BUS_PORT` | Variable | Event bus port | `9092` | ✅ | ❌ |
| `SONAR_PROJECT_KEY` | Variable | SonarCloud project key | `my-org_user-management-service` | ✅ | ❌ |
| `SONAR_ORGANIZATION` | Variable | SonarCloud organization key | `my-organization` | ✅ | ❌ |
| `SNYK_ORG_ID` | Variable | Snyk organization ID | `12345678-abcd-1234-efgh-123456789012` | ✅ | ❌ |
| `DEPLOYMENT_URL` | Variable | Base URL for smoke tests | `https://dev.user-management.example.com` | ✅ | ❌ |
| `NOTIFICATION_EMAIL` | Variable | Email for failure notifications (optional) | `devops@example.com` | ❌ | ❌ |

---

## Third-Party Service Setup

### 1. Google Cloud Platform (GCP) Setup

#### Create Service Account
```bash
# Create service account
gcloud iam service-accounts create gitlab-ci-deployer \
  --display-name="GitLab CI Deployer" \
  --project=YOUR_PROJECT_ID

# Grant necessary permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Create and download key
gcloud iam service-accounts keys create key.json \
  --iam-account=gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Base64 encode the key for GitLab
cat key.json | base64 -w 0 > key.base64

# Copy the content of key.base64 to GKE_SERVICE_ACCOUNT_KEY variable
cat key.base64
```

#### Create GKE Cluster (if not exists)
```bash
gcloud container clusters create production-gke-cluster \
  --region=us-central1 \
  --num-nodes=3 \
  --machine-type=n1-standard-2 \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=10 \
  --enable-autorepair \
  --enable-autoupgrade
```

### 2. SonarCloud Setup

1. Go to [SonarCloud](https://sonarcloud.io)
2. Sign in with your GitLab account
3. Click **+** → **Analyze new project**
4. Select your GitLab project
5. Note your:
   - **Organization Key** → `SONAR_ORGANIZATION`
   - **Project Key** → `SONAR_PROJECT_KEY`
6. Go to **My Account** → **Security** → Generate token
7. Copy token → `SONAR_TOKEN`

### 3. Snyk Setup

1. Go to [Snyk](https://snyk.io)
2. Create account and organization
3. Go to **Settings** → **General**
4. Copy **Organization ID** → `SNYK_ORG_ID`
5. Go to **Settings** → **Service Accounts** (or use personal token)
6. Generate token → `SNYK_TOKEN`

### 4. Slack Notifications Setup

1. Go to your Slack workspace
2. Navigate to **Apps** → Search for "Incoming Webhooks"
3. Click **Add to Slack**
4. Select channel (e.g., `#devops-alerts`)
5. Copy webhook URL → `SLACK_WEBHOOK_URL`

---

## Kubernetes Resources Setup

### 1. Create Namespace
```bash
kubectl create namespace development
```

### 2. Verify Dependencies

#### PostgreSQL Database
```bash
# Test connectivity
kubectl run -it --rm pg-test --image=postgres:15-alpine --restart=Never -- \
  psql -h YOUR_DB_HOST -U YOUR_DB_USER -d YOUR_DB_NAME -c "SELECT 1"
```

#### Redis Cache
```bash
# Test connectivity
kubectl run -it --rm redis-test --image=redis:7-alpine --restart=Never -- \
  redis-cli -h YOUR_REDIS_HOST -p YOUR_REDIS_PORT -a YOUR_REDIS_PASSWORD PING
```

#### Event Bus
```bash
# Test connectivity (adjust for your event bus type)
kubectl run -it --rm eventbus-test --image=busybox --restart=Never -- \
  nc -zv YOUR_EVENT_BUS_HOST YOUR_EVENT_BUS_PORT
```

---

## Dockerfile Requirements

Create a `Dockerfile` in your project root:

```dockerfile
# Stage 1: Build stage (optional if using Maven in CI)
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

# Stage 2: Runtime stage
FROM eclipse-temurin:17-jre-alpine

# Metadata
ARG SERVICE_VERSION=unknown
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG SERVICE_ID=SVC-001

LABEL org.opencontainers.image.title="User Management Service" \
      org.opencontainers.image.version="${SERVICE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      com.service.id="${SERVICE_ID}" \
      com.service.name="user-management-service"

# Create app user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy JAR from CI build
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} app.jar

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Run application
ENTRYPOINT ["java", \
            "-XX:+UseContainerSupport", \
            "-XX:MaxRAMPercentage=75.0", \
            "-Djava.security.egd=file:/dev/./urandom", \
            "-jar", \
            "app.jar"]
```

---

## Kubernetes Manifests

Create a `k8s/` directory with the following manifests:

### `k8s/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-management-service
  namespace: development
  labels:
    app: user-management-service
    service-id: SVC-001
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: user-management-service
  template:
    metadata:
      labels:
        app: user-management-service
        service-id: SVC-001
    spec:
      containers:
      - name: user-management-service
        image: registry.gitlab.com/YOUR_GROUP/YOUR_PROJECT/user-management-service:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        # Database Configuration
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:postgresql://$(DB_HOST):$(DB_PORT)/$(DB_NAME)"
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: db-username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: db-password

        # Redis Configuration
        - name: SPRING_REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: redis-host
        - name: SPRING_REDIS_PORT
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: redis-port
        - name: SPRING_REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: redis-password

        # JWT Configuration
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: jwt-secret

        # OAuth Configuration
        - name: OAUTH_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: oauth-client-secret

        # Event Bus Configuration
        - name: EVENT_BUS_HOST
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: eventbus-host
        - name: EVENT_BUS_PORT
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: eventbus-port
        - name: EVENT_BUS_USERNAME
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: eventbus-username
        - name: EVENT_BUS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: eventbus-password

        # Service Configuration
        - name: SERVICE_ID
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: service-id

        # ConfigMap references
        envFrom:
        - configMapRef:
            name: user-management-service-config

        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"

        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

      imagePullSecrets:
      - name: gitlab-registry-credentials
```

### `k8s/service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: user-management-service
  namespace: development
  labels:
    app: user-management-service
    service-id: SVC-001
spec:
  type: LoadBalancer
  selector:
    app: user-management-service
  ports:
  - name: http
    port: 80
    targetPort: 8080
    protocol: TCP
  sessionAffinity: ClientIP
```

### `k8s/hpa.yaml` (Optional - Horizontal Pod Autoscaler)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-management-service-hpa
  namespace: development
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user-management-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
```

### Create GitLab Registry Secret
```bash
kubectl create secret docker-registry gitlab-registry-credentials \
  --docker-server=registry.gitlab.com \
  --docker-username=YOUR_GITLAB_USERNAME \
  --docker-password=YOUR_GITLAB_ACCESS_TOKEN \
  --namespace=development
```

---

## Verification & Testing

### 1. Verify Pipeline Configuration
```bash
# Validate YAML syntax locally
docker run --rm -v $(pwd):/workspace mikefarah/yq:latest eval '.stages' /workspace/.gitlab-ci.yml
```

### 2. Test Local Docker Build
```bash
# Build locally
docker build -t user-management-service:test .

# Run locally
docker run -p 8080:8080 \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/testdb \
  -e SPRING_DATASOURCE_USERNAME=testuser \
  -e SPRING_DATASOURCE_PASSWORD=testpass \
  user-management-service:test
```

### 3. Manual Pipeline Trigger
1. Go to **CI/CD → Pipelines** in GitLab
2. Click **Run Pipeline**
3. Select branch (e.g., `develop`)
4. Click **Run Pipeline**

### 4. Monitor Pipeline Execution
Watch the pipeline stages execute:
- ✅ Validate
- ✅ Build
- ✅ Test (Unit + Integration)
- ✅ Analyze (SonarCloud)
- ✅ Security (Snyk + Dependency Check)
- ✅ Package (JAR + Docker + Trivy)
- ✅ Deploy (Pre-check + Deployment)
- ✅ Smoke Test
- ✅ Notify

---

## Troubleshooting

### Common Issues

#### 1. **GKE Authentication Failed**
```
Error: Unable to connect to the server: x509: certificate signed by unknown authority
```

**Solution:**
- Verify `GKE_SERVICE_ACCOUNT_KEY` is base64-encoded correctly
- Ensure service account has `roles/container.developer` permission
- Check GKE cluster name and region are correct

```bash
# Re-encode service account key
cat key.json | base64 -w 0
```

#### 2. **PostgreSQL Connection Failed**
```
ERROR: PostgreSQL Database is not reachable!
```

**Solution:**
- Verify `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD` variables
- Check network connectivity from GKE to PostgreSQL
- Ensure PostgreSQL allows connections from GKE cluster IP range
- Check firewall rules

```bash
# Test from within cluster
kubectl run -it pg-debug --image=postgres:15-alpine --rm --restart=Never -- \
  psql -h YOUR_DB_HOST -U YOUR_DB_USER -c "SELECT 1"
```

#### 3. **Redis Connection Failed**
```
ERROR: Redis Cache is not reachable!
```

**Solution:**
- Verify `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` variables
- Check Redis authentication is enabled/disabled correctly
- Test connectivity from GKE

```bash
# Test from within cluster
kubectl run -it redis-debug --image=redis:7-alpine --rm --restart=Never -- \
  redis-cli -h YOUR_REDIS_HOST PING
```

#### 4. **Snyk Scan Fails**
```
Error: Invalid Snyk token
```

**Solution:**
- Regenerate Snyk token from https://app.snyk.io/account
- Ensure `SNYK_TOKEN` and `SNYK_ORG_ID` are set correctly
- Check if organization has access to project

#### 5. **SonarCloud Analysis Fails**
```
Error: Not authorized. Please check the quality gate.
```

**Solution:**
- Verify `SONAR_TOKEN`, `SONAR_PROJECT_KEY`, `SONAR_ORGANIZATION`
- Ensure project exists in SonarCloud
- Check token permissions (needs "Execute Analysis")

#### 6. **Docker Build Out of Memory**
```
Error: failed to solve: process "/bin/sh -c mvn package" did not complete successfully
```

**Solution:**
- Increase Docker daemon memory in GitLab Runner configuration
- Use multi-stage builds (already implemented)
- Add `MAVEN_OPTS: "-Xmx1024m"` to job

#### 7. **Smoke Tests Fail**
```
ERROR: Health endpoint not reachable
```

**Solution:**
- Increase `sleep` time before smoke tests (currently 30s)
- Check pod logs: `kubectl logs -n development -l app=user-management-service`
- Verify `DEPLOYMENT_URL` variable is correct
- Check ingress/load balancer configuration

```bash
# Check pod status
kubectl get pods -n development -l app=user-management-service

# View logs
kubectl logs -n development -l app=user-management-service --tail=100

# Describe pod for events
kubectl describe pod -n development -l app=user-management-service
```

#### 8. **Event Bus Check Warning**
```
WARNING: Event Bus connectivity check failed!
```

**Solution:**
- This is set to non-blocking (won't fail pipeline)
- Verify `EVENT_BUS_HOST` and `EVENT_BUS_PORT`
- Adjust check command based on your event bus type (Kafka, RabbitMQ, AWS SNS)

---

## Security Best Practices

### 1. **Secrets Management**
- ✅ All sensitive variables are marked as "Protected" and "Masked"
- ✅ Secrets stored in Kubernetes Secrets, not ConfigMaps
- ✅ Never commit secrets to version control
- Consider using external secret managers:
  - Google Secret Manager
  - HashiCorp Vault
  - AWS Secrets Manager

### 2. **Image Security**
- ✅ Using official base images (eclipse-temurin)
- ✅ Running as non-root user (appuser)
- ✅ Trivy scanning for vulnerabilities
- ✅ Multi-stage builds to reduce attack surface

### 3. **Network Security**
- Configure Network Policies in Kubernetes
- Use Private GKE clusters
- Enable Pod Security Standards

### 4. **Access Control**
- Use service accounts with minimal permissions
- Enable RBAC in GKE
- Rotate credentials regularly

---

## Next Steps

1. **Set up Staging Environment**
   - Duplicate deployment configuration for staging namespace
   - Add manual approval gates for production

2. **Implement Blue-Green Deployment**
   - Use Kubernetes Services with label selectors
   - Zero-downtime deployments

3. **Add Performance Testing**
   - Integrate JMeter or Gatling tests
   - Run after smoke tests

4. **Set Up Monitoring**
   - Integrate with Prometheus/Grafana
   - Set up alerts for failed deployments

5. **Implement GitOps**
   - Consider using ArgoCD or Flux
   - Declarative deployment management

---

## Support & Resources

- **GitLab CI/CD Docs:** https://docs.gitlab.com/ee/ci/
- **GKE Documentation:** https://cloud.google.com/kubernetes-engine/docs
- **SonarCloud Docs:** https://docs.sonarcloud.io/
- **Snyk Documentation:** https://docs.snyk.io/
- **Spring Boot Actuator:** https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html

---

## Quick Reference Card

### Essential Commands

```bash
# View pipeline status
glab ci view

# Trigger manual pipeline
glab ci run

# View logs
glab ci trace <job-id>

# Check GKE pods
kubectl get pods -n development -l app=user-management-service

# View pod logs
kubectl logs -n development -l app=user-management-service -f

# Describe deployment
kubectl describe deployment user-management-service -n development

# Rollback deployment
kubectl rollout undo deployment/user-management-service -n development

# Check service endpoints
kubectl get svc -n development user-management-service

# Port-forward for local testing
kubectl port-forward -n development svc/user-management-service 8080:80
```

### Variable Checklist

Before running the pipeline, ensure these are set:

#### Critical (Must Have)
- [ ] `GKE_SERVICE_ACCOUNT_KEY`
- [ ] `GCP_PROJECT_ID`
- [ ] `GKE_CLUSTER_NAME`
- [ ] `GKE_REGION`
- [ ] `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`
- [ ] `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`

#### For Security Scanning
- [ ] `SNYK_TOKEN`, `SNYK_ORG_ID`
- [ ] `SONAR_TOKEN`, `SONAR_PROJECT_KEY`, `SONAR_ORGANIZATION`

#### For Application
- [ ] `JWT_SECRET`
- [ ] `OAUTH_CLIENT_SECRET`
- [ ] `EVENT_BUS_HOST`, `EVENT_BUS_PORT`, `EVENT_BUS_USERNAME`, `EVENT_BUS_PASSWORD`

#### For Notifications
- [ ] `SLACK_WEBHOOK_URL`
- [ ] `DEPLOYMENT_URL`

---

**Document Version:** 1.0
**Last Updated:** 2026-01-12
**Maintained By:** DevOps Team
