# GitLab CI/CD Setup Guide
## User Management Service (SVC-001)

This guide explains how to configure GitLab CI/CD variables and dependencies to support the User Management Service pipeline.

---

## Table of Contents
1. [Required GitLab CI/CD Variables](#required-gitlab-cicd-variables)
2. [Kubernetes Manifests Setup](#kubernetes-manifests-setup)
3. [Dockerfile Configuration](#dockerfile-configuration)
4. [Pre-Deployment Checklist](#pre-deployment-checklist)
5. [GitLab Runner Configuration](#gitlab-runner-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Required GitLab CI/CD Variables

Navigate to **Settings > CI/CD > Variables** in your GitLab project and add the following variables:

### 1. Container Registry Variables

| Variable | Type | Protected | Masked | Description |
|----------|------|-----------|--------|-------------|
| `CI_REGISTRY` | Variable | No | No | GitLab Container Registry URL (auto-provided) |
| `CI_REGISTRY_USER` | Variable | No | No | Registry username (auto-provided) |
| `CI_REGISTRY_PASSWORD` | Variable | No | Yes | Registry password (auto-provided) |

> **Note:** These are automatically provided by GitLab. Verify they are available.

---

### 2. Database Configuration (PostgreSQL)

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `DB_HOST` | Variable | Yes | No | PostgreSQL host address | `postgres.example.com` |
| `DB_PORT` | Variable | Yes | No | PostgreSQL port | `5432` |
| `DB_NAME` | Variable | Yes | No | Database name | `userservice_prod` |
| `DB_USERNAME` | Variable | Yes | No | Database username | `userservice_app` |
| `DB_PASSWORD` | Variable | Yes | Yes | Database password | `your-secure-password` |

---

### 3. Redis Cache Configuration

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `REDIS_HOST` | Variable | Yes | No | Redis host address | `redis.example.com` |
| `REDIS_PORT` | Variable | Yes | No | Redis port | `6379` |
| `REDIS_PASSWORD` | Variable | Yes | Yes | Redis authentication password | `redis-secure-password` |

---

### 4. Event Bus Configuration

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `EVENT_BUS_HOST` | Variable | Yes | No | Event bus host (Kafka/RabbitMQ) | `kafka.example.com` |
| `EVENT_BUS_PORT` | Variable | Yes | No | Event bus port | `9092` (Kafka) or `5672` (RabbitMQ) |
| `EVENT_BUS_USERNAME` | Variable | Yes | No | Event bus username | `userservice` |
| `EVENT_BUS_PASSWORD` | Variable | Yes | Yes | Event bus password | `eventbus-password` |

---

### 5. Security & Authentication Variables

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `JWT_SECRET` | Variable | Yes | Yes | JWT signing secret (min 256-bit) | `your-jwt-secret-key-min-32-chars` |
| `OAUTH_CLIENT_SECRET` | Variable | Yes | Yes | OAuth 2.0 client secret | `oauth-client-secret` |

---

### 6. Google Kubernetes Engine (GKE) Configuration

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `GKE_SERVICE_ACCOUNT_KEY` | File | Yes | Yes | Base64-encoded GCP service account JSON key | `<base64-encoded-json>` |
| `GCP_PROJECT_ID` | Variable | Yes | No | Google Cloud project ID | `my-gcp-project` |
| `GKE_CLUSTER_NAME` | Variable | Yes | No | GKE cluster name | `medication-mgmt-cluster` |
| `GKE_REGION` | Variable | Yes | No | GKE cluster region | `us-central1` |

**To create the GKE service account key:**
```bash
# Create service account
gcloud iam service-accounts create gitlab-ci-deployer \
  --display-name="GitLab CI Deployer"

# Grant necessary permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

# Create and download key
gcloud iam service-accounts keys create key.json \
  --iam-account=gitlab-ci-deployer@PROJECT_ID.iam.gserviceaccount.com

# Base64 encode the key
cat key.json | base64 -w 0 > key.json.b64

# Copy the contents of key.json.b64 to GitLab variable GKE_SERVICE_ACCOUNT_KEY
```

---

### 7. Security Scanning Tools

#### SonarCloud Configuration

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `SONAR_TOKEN` | Variable | Yes | Yes | SonarCloud authentication token | `squ_abc123...` |
| `SONAR_PROJECT_KEY` | Variable | No | No | SonarCloud project key | `user-management-service` |
| `SONAR_ORGANIZATION` | Variable | No | No | SonarCloud organization | `my-organization` |

**To obtain SonarCloud token:**
1. Go to https://sonarcloud.io/account/security
2. Generate a new token
3. Add it to GitLab CI/CD variables

#### Snyk Configuration

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `SNYK_TOKEN` | Variable | Yes | Yes | Snyk API authentication token | `abc-123-def-456` |
| `SNYK_ORG_ID` | Variable | No | No | Snyk organization ID | `my-org-id` |

**To obtain Snyk token:**
1. Go to https://app.snyk.io/account
2. Copy your API token
3. Add it to GitLab CI/CD variables

---

### 8. Notification Configuration

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `SLACK_WEBHOOK_URL` | Variable | No | Yes | Slack incoming webhook URL | `https://hooks.slack.com/services/...` |
| `NOTIFICATION_EMAIL` | Variable | No | No | Email for failure notifications | `devops-team@example.com` |

**To create a Slack webhook:**
1. Go to your Slack workspace settings
2. Navigate to Apps > Incoming Webhooks
3. Add a new webhook to a channel
4. Copy the webhook URL

---

### 9. Deployment Configuration

| Variable | Type | Protected | Masked | Description | Example Value |
|----------|------|-----------|--------|-------------|---------------|
| `DEPLOYMENT_URL` | Variable | Yes | No | Base URL for smoke tests | `https://dev.user-management.example.com` |
| `KUBE_NAMESPACE` | Variable | Yes | No | Kubernetes namespace (optional override) | `development` |

---

## Kubernetes Manifests Setup

Create the following Kubernetes manifest files in your repository under `k8s/` directory:

### `k8s/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-management-service
  labels:
    app: user-management-service
    service-id: SVC-001
spec:
  replicas: 3
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
        image: registry.gitlab.com/your-group/user-management-service:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        - containerPort: 8081
          name: management
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

        # Service Metadata
        - name: SERVICE_ID
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: service-id
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: db-host
        - name: DB_PORT
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: db-port
        - name: DB_NAME
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: db-name

        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"

        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8081
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

        startupProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8081
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 30

      imagePullSecrets:
      - name: gitlab-registry-secret

      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - user-management-service
              topologyKey: kubernetes.io/hostname
```

### `k8s/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: user-management-service
  labels:
    app: user-management-service
    service-id: SVC-001
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  - port: 8081
    targetPort: 8081
    protocol: TCP
    name: management
  selector:
    app: user-management-service
---
apiVersion: v1
kind: Service
metadata:
  name: user-management-service-lb
  labels:
    app: user-management-service
    service-id: SVC-001
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 8080
    protocol: TCP
    name: https
  selector:
    app: user-management-service
```

### `k8s/hpa.yaml` (Horizontal Pod Autoscaler)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-management-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user-management-service
  minReplicas: 3
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

---

## Dockerfile Configuration

Create a `Dockerfile` in the root of your repository:

```dockerfile
# Multi-stage build for Spring Boot application
FROM eclipse-temurin:17-jre-alpine AS builder
WORKDIR /app
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} application.jar
RUN java -Djarmode=layertools -jar application.jar extract

# Final runtime image
FROM eclipse-temurin:17-jre-alpine

# Install dependencies
RUN apk add --no-cache curl wget

# Create non-root user
RUN addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S appuser -G appuser

WORKDIR /app

# Copy application layers
COPY --from=builder --chown=appuser:appuser /app/dependencies/ ./
COPY --from=builder --chown=appuser:appuser /app/spring-boot-loader/ ./
COPY --from=builder --chown=appuser:appuser /app/snapshot-dependencies/ ./
COPY --from=builder --chown=appuser:appuser /app/application/ ./

# Metadata labels
ARG SERVICE_VERSION
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${SERVICE_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.title="User Management Service" \
      org.opencontainers.image.description="Core service for user authentication, authorization, and profile management" \
      com.service.id="SVC-001" \
      com.service.name="user-management-service"

# Switch to non-root user
USER appuser

# Expose ports
EXPOSE 8080 8081

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8081/actuator/health || exit 1

# JVM configuration for container environments
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:InitialRAMPercentage=50.0 \
               -XX:+UseG1GC \
               -XX:+ParallelRefProcEnabled \
               -XX:+UseStringDeduplication \
               -Djava.security.egd=file:/dev/./urandom"

# Run application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
```

---

## Pre-Deployment Checklist

Before running the pipeline, ensure:

### 1. GitLab Runner Configuration
- [ ] GitLab Runners are configured with Docker executor
- [ ] Runners have `privileged` tag for Docker-in-Docker builds
- [ ] Runners have access to GKE (network connectivity)

### 2. External Dependencies
- [ ] PostgreSQL database is provisioned and accessible
- [ ] Redis cache is deployed and configured
- [ ] Event Bus (Kafka/RabbitMQ) is running
- [ ] Database schema migrations are prepared

### 3. GKE Cluster Setup
- [ ] GKE cluster is created and running
- [ ] `kubectl` access is configured for CI service account
- [ ] Namespace `development` exists (or will be created by pipeline)
- [ ] Load balancer/Ingress is configured for external access

### 4. Security
- [ ] All secrets are marked as "Masked" in GitLab
- [ ] Service account has minimal required permissions
- [ ] JWT secret is cryptographically strong (min 256-bit)
- [ ] OAuth credentials are valid

### 5. Monitoring & Notifications
- [ ] Slack webhook is configured and tested
- [ ] SonarCloud project is created
- [ ] Snyk organization is set up

---

## GitLab Runner Configuration

### Recommended Runner Configuration

Add to `/etc/gitlab-runner/config.toml`:

```toml
[[runners]]
  name = "docker-privileged-runner"
  url = "https://gitlab.com/"
  token = "YOUR_RUNNER_TOKEN"
  executor = "docker"
  [runners.docker]
    tls_verify = false
    image = "docker:24-dind"
    privileged = true
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]
    shm_size = 0
  [runners.cache]
    Type = "s3"
    Shared = true
    [runners.cache.s3]
      ServerAddress = "s3.amazonaws.com"
      BucketName = "gitlab-runner-cache"
      BucketLocation = "us-east-1"
```

### Register Runner with Tags

```bash
gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com/" \
  --registration-token "YOUR_REGISTRATION_TOKEN" \
  --executor "docker" \
  --docker-image "docker:24-dind" \
  --docker-privileged \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --tag-list "docker,privileged" \
  --description "Docker Privileged Runner"
```

---

## Troubleshooting

### Common Issues

#### 1. **Docker Build Fails with Permission Errors**
**Solution:**
- Ensure runner has `privileged = true` in configuration
- Verify Docker-in-Docker service is running
- Check runner has `privileged` tag

#### 2. **GKE Authentication Fails**
**Solution:**
- Verify `GKE_SERVICE_ACCOUNT_KEY` is base64-encoded correctly
- Check service account has `roles/container.developer` role
- Ensure cluster name and region are correct

#### 3. **Database Connection Fails in Tests**
**Solution:**
- Verify PostgreSQL service is defined in `.gitlab-ci.yml`
- Check service alias matches connection string
- Ensure `POSTGRES_*` variables are set correctly

#### 4. **Smoke Tests Fail**
**Solution:**
- Verify `DEPLOYMENT_URL` is set correctly
- Check service has fully started (increase sleep time)
- Ensure LoadBalancer/Ingress is configured
- Check network policies allow egress from CI runner

#### 5. **Maven Dependencies Download Slowly**
**Solution:**
- Configure S3 cache for GitLab Runner
- Use internal Maven repository mirror
- Increase runner timeout values

#### 6. **Snyk/Trivy Scan Failures**
**Solution:**
- Set `allow_failure: true` initially for security jobs
- Review and suppress false positives
- Update dependencies to fix vulnerabilities

---

## Environment-Specific Configurations

### Development Environment
- Namespace: `development`
- Replicas: 3
- Resources: Low allocation
- Auto-deployment: Enabled on `develop` branch

### Staging Environment
To add staging, duplicate `deploy:development` job:

```yaml
deploy:staging:
  extends: .deploy_template
  stage: deploy
  variables:
    KUBE_NAMESPACE: "staging"
    DEPLOYMENT_URL: "https://staging.user-management.example.com"
  environment:
    name: staging
    url: https://staging.user-management.example.com
  only:
    - main
```

### Production Environment
For production deployment:

```yaml
deploy:production:
  extends: .deploy_template
  stage: deploy
  variables:
    KUBE_NAMESPACE: "production"
    DEPLOYMENT_URL: "https://api.user-management.example.com"
  environment:
    name: production
    url: https://api.user-management.example.com
  when: manual
  only:
    - tags
```

---

## Security Best Practices

1. **Rotate Secrets Regularly**
   - JWT secrets should be rotated every 90 days
   - Database passwords every 60 days
   - Service account keys every 180 days

2. **Scan Dependencies**
   - Review Snyk reports weekly
   - Update dependencies monthly
   - Monitor CVE databases

3. **Access Control**
   - Use protected branches for main/develop
   - Require code review before merge
   - Enable deployment approvals for production

4. **Audit Logs**
   - Enable GitLab audit logs
   - Monitor GKE audit logs
   - Track deployment history

---

## Additional Resources

- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [Google Kubernetes Engine Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Spring Boot Docker Best Practices](https://spring.io/guides/topicals/spring-boot-docker/)
- [Snyk Documentation](https://docs.snyk.io/)
- [SonarCloud Documentation](https://docs.sonarcloud.io/)

---

## Support

For issues or questions:
- Open an issue in the GitLab repository
- Contact DevOps team at: devops-team@example.com
- Slack channel: #devops-support

---

**Document Version:** 1.0
**Last Updated:** 2026-01-12
**Maintained By:** DevOps Team
