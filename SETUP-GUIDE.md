# GitLab CI/CD Setup Guide
## User Management Service (SVC-001)

This guide provides step-by-step instructions for configuring the GitLab CI/CD pipeline for the User Management Service.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Required CI/CD Variables](#required-cicd-variables)
3. [Creating Kubernetes Secrets](#creating-kubernetes-secrets)
4. [Dockerfile Configuration](#dockerfile-configuration)
5. [Kubernetes Manifests](#kubernetes-manifests)
6. [SonarCloud Setup](#sonarcloud-setup)
7. [Snyk Setup](#snyk-setup)
8. [Slack Notifications Setup](#slack-notifications-setup)
9. [Testing the Pipeline](#testing-the-pipeline)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before setting up the CI/CD pipeline, ensure you have:

- GitLab repository with appropriate permissions
- Google Cloud Platform (GCP) account with GKE cluster
- SonarCloud account and organization
- Snyk account and organization
- Docker registry access (GitLab Container Registry)
- Slack workspace (for notifications)

---

## Required CI/CD Variables

Navigate to **Settings > CI/CD > Variables** in your GitLab project and add the following variables:

### 1. Docker Registry Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `CI_REGISTRY_USER` | `<gitlab-username>` | ✓ | ✗ | GitLab registry username (auto-provided) |
| `CI_REGISTRY_PASSWORD` | `<gitlab-token>` | ✓ | ✓ | GitLab registry password (auto-provided) |
| `CI_REGISTRY` | `registry.gitlab.com` | ✗ | ✗ | GitLab registry URL (auto-provided) |

> **Note:** These are typically auto-configured by GitLab. Verify they exist.

---

### 2. Google Cloud Platform (GCP) & GKE Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `GKE_SERVICE_ACCOUNT_KEY` | `<base64-encoded-json>` | ✓ | ✓ | Base64-encoded GCP service account key |
| `GCP_PROJECT_ID` | `your-gcp-project-id` | ✓ | ✗ | GCP project identifier |
| `GKE_CLUSTER_NAME` | `your-cluster-name` | ✓ | ✗ | Name of your GKE cluster |
| `GKE_REGION` | `us-central1` | ✗ | ✗ | GCP region for GKE cluster |

**Creating the Service Account Key:**

```bash
# Create service account
gcloud iam service-accounts create gitlab-ci-deployer \
    --display-name "GitLab CI/CD Deployer"

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

# Base64 encode the key
cat key.json | base64 > key-base64.txt
```

Use the content of `key-base64.txt` as the value for `GKE_SERVICE_ACCOUNT_KEY`.

---

### 3. PostgreSQL Database Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `DB_HOST` | `postgres.example.com` | ✓ | ✗ | PostgreSQL host address |
| `DB_PORT` | `5432` | ✗ | ✗ | PostgreSQL port |
| `DB_NAME` | `userdb` | ✓ | ✗ | Database name |
| `DB_USERNAME` | `admin` | ✓ | ✓ | Database username |
| `DB_PASSWORD` | `<secure-password>` | ✓ | ✓ | Database password |

---

### 4. Redis Cache Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `REDIS_HOST` | `redis.example.com` | ✓ | ✗ | Redis host address |
| `REDIS_PORT` | `6379` | ✗ | ✗ | Redis port |
| `REDIS_PASSWORD` | `<secure-password>` | ✓ | ✓ | Redis authentication password |

---

### 5. Event Bus Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `EVENT_BUS_HOST` | `kafka.example.com` | ✓ | ✗ | Event bus host (Kafka/RabbitMQ) |
| `EVENT_BUS_PORT` | `9092` | ✗ | ✗ | Event bus port |
| `EVENT_BUS_USERNAME` | `eventbus-user` | ✓ | ✓ | Event bus username |
| `EVENT_BUS_PASSWORD` | `<secure-password>` | ✓ | ✓ | Event bus password |

---

### 6. Security & Authentication Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `JWT_SECRET` | `<random-256-bit-secret>` | ✓ | ✓ | JWT signing secret |
| `OAUTH_CLIENT_SECRET` | `<oauth-secret>` | ✓ | ✓ | OAuth 2.0 client secret |

**Generating a JWT Secret:**

```bash
# Generate a secure random secret
openssl rand -base64 64 | tr -d '\n'
```

---

### 7. SonarCloud Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `SONAR_TOKEN` | `<sonar-token>` | ✓ | ✓ | SonarCloud authentication token |
| `SONAR_PROJECT_KEY` | `your-org_user-mgmt-svc` | ✗ | ✗ | SonarCloud project key |
| `SONAR_ORGANIZATION` | `your-organization` | ✗ | ✗ | SonarCloud organization name |

---

### 8. Snyk Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `SNYK_TOKEN` | `<snyk-api-token>` | ✓ | ✓ | Snyk authentication token |
| `SNYK_ORG_ID` | `<your-org-id>` | ✗ | ✗ | Snyk organization ID |

---

### 9. Notification Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `SLACK_WEBHOOK_URL` | `https://hooks.slack.com/...` | ✓ | ✓ | Slack incoming webhook URL |
| `NOTIFICATION_EMAIL` | `devops@example.com` | ✗ | ✗ | Email for failure notifications |

---

### 10. Deployment Configuration Variables

| Variable Name | Value | Protected | Masked | Description |
|--------------|-------|-----------|---------|-------------|
| `DEPLOYMENT_URL` | `https://dev.user-management.example.com` | ✗ | ✗ | Base URL for smoke tests |

---

## Creating Kubernetes Secrets

The pipeline creates secrets dynamically, but you can pre-create them for security:

```bash
# Set your namespace
export NAMESPACE=development

# Create PostgreSQL secret
kubectl create secret generic user-management-service-secrets \
  --from-literal=db-username="${DB_USERNAME}" \
  --from-literal=db-password="${DB_PASSWORD}" \
  --from-literal=redis-password="${REDIS_PASSWORD}" \
  --from-literal=jwt-secret="${JWT_SECRET}" \
  --from-literal=oauth-client-secret="${OAUTH_CLIENT_SECRET}" \
  --from-literal=eventbus-username="${EVENT_BUS_USERNAME}" \
  --from-literal=eventbus-password="${EVENT_BUS_PASSWORD}" \
  --namespace=${NAMESPACE}

# Create ConfigMap
kubectl create configmap user-management-service-config \
  --from-literal=db-host="${DB_HOST}" \
  --from-literal=db-port="${DB_PORT}" \
  --from-literal=db-name="${DB_NAME}" \
  --from-literal=redis-host="${REDIS_HOST}" \
  --from-literal=redis-port="${REDIS_PORT}" \
  --from-literal=eventbus-host="${EVENT_BUS_HOST}" \
  --from-literal=eventbus-port="${EVENT_BUS_PORT}" \
  --from-literal=service-id="SVC-001" \
  --namespace=${NAMESPACE}

# Create GitLab registry pull secret
kubectl create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username="${CI_REGISTRY_USER}" \
  --docker-password="${CI_REGISTRY_PASSWORD}" \
  --namespace=${NAMESPACE}
```

---

## Dockerfile Configuration

Create a `Dockerfile` in your project root:

```dockerfile
FROM eclipse-temurin:17-jre-alpine

# Metadata labels
LABEL maintainer="DevOps Team <devops@example.com>"
LABEL service.name="user-management-service"
LABEL service.id="SVC-001"
LABEL org.opencontainers.image.description="User Authentication & Profile Management Service"

# Build arguments
ARG JAR_FILE=target/*.jar
ARG SERVICE_VERSION
ARG BUILD_DATE
ARG VCS_REF

# Additional labels
LABEL org.opencontainers.image.version="${SERVICE_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"

# Create non-root user for security
RUN addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S appuser -G appuser

# Set working directory
WORKDIR /app

# Copy application JAR
COPY --chown=appuser:appuser ${JAR_FILE} app.jar

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 8080

# Health check configuration
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# JVM optimization for containers
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UseG1GC \
               -XX:+ExitOnOutOfMemoryError \
               -Djava.security.egd=file:/dev/./urandom"

# Run the application
ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar app.jar"]
```

---

## Kubernetes Manifests

Create a `k8s/` directory with the following files:

### k8s/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-management-service
  namespace: development
  labels:
    app: user-management-service
    service.id: SVC-001
    tier: backend
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
        service.id: SVC-001
        tier: backend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      serviceAccountName: user-management-service
      containers:
      - name: user-management-service
        image: registry.gitlab.com/your-org/user-management-service:latest
        imagePullPolicy: Always
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "production"
        - name: SERVICE_ID
          valueFrom:
            configMapKeyRef:
              name: user-management-service-config
              key: service-id
        - name: SPRING_DATASOURCE_URL
          value: jdbc:postgresql://$(DB_HOST):$(DB_PORT)/$(DB_NAME)
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
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: jwt-secret
        - name: OAUTH_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: user-management-service-secrets
              key: oauth-client-secret
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
        securityContext:
          runAsNonRoot: true
          runAsUser: 1001
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
          readOnlyRootFilesystem: false
      imagePullSecrets:
      - name: gitlab-registry
      securityContext:
        fsGroup: 1001
```

### k8s/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: user-management-service
  namespace: development
  labels:
    app: user-management-service
    service.id: SVC-001
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: http
    protocol: TCP
    name: http
  selector:
    app: user-management-service
```

### k8s/hpa.yaml

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
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
```

---

## SonarCloud Setup

1. **Create SonarCloud Account:**
   - Visit https://sonarcloud.io
   - Sign in with your GitLab account

2. **Create Organization:**
   - Click "+" in top right > "Create new organization"
   - Link to your GitLab account

3. **Create Project:**
   - Click "+" > "Analyze new project"
   - Select your GitLab repository
   - Note the **Project Key** and **Organization**

4. **Generate Token:**
   - Click on your avatar > "My Account" > "Security"
   - Generate new token with name "GitLab CI"
   - Copy and add to GitLab CI/CD variables as `SONAR_TOKEN`

5. **Add to pom.xml:**

```xml
<properties>
    <sonar.organization>your-organization</sonar.organization>
    <sonar.host.url>https://sonarcloud.io</sonar.host.url>
</properties>

<build>
    <plugins>
        <plugin>
            <groupId>org.sonarsource.scanner.maven</groupId>
            <artifactId>sonar-maven-plugin</artifactId>
            <version>3.10.0.2594</version>
        </plugin>
        <plugin>
            <groupId>org.jacoco</groupId>
            <artifactId>jacoco-maven-plugin</artifactId>
            <version>0.8.11</version>
            <executions>
                <execution>
                    <goals>
                        <goal>prepare-agent</goal>
                    </goals>
                </execution>
                <execution>
                    <id>report</id>
                    <phase>test</phase>
                    <goals>
                        <goal>report</goal>
                    </goals>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

---

## Snyk Setup

1. **Create Snyk Account:**
   - Visit https://snyk.io
   - Sign up or log in

2. **Get API Token:**
   - Go to Account Settings
   - Under "API Token", generate or copy your token
   - Add to GitLab CI/CD variables as `SNYK_TOKEN`

3. **Get Organization ID:**
   - Go to Settings > General
   - Copy your Organization ID
   - Add to GitLab CI/CD variables as `SNYK_ORG_ID`

4. **Integrate with GitLab:**
   - In Snyk, go to Integrations
   - Add GitLab integration
   - Select your repository

---

## Slack Notifications Setup

1. **Create Incoming Webhook:**
   - Go to https://api.slack.com/apps
   - Create New App > From scratch
   - Name it "GitLab CI Notifier"
   - Select your workspace

2. **Add Incoming Webhooks:**
   - Click "Incoming Webhooks"
   - Activate Incoming Webhooks
   - Click "Add New Webhook to Workspace"
   - Select the channel for notifications
   - Copy the Webhook URL

3. **Add to GitLab:**
   - Add webhook URL to GitLab CI/CD variables as `SLACK_WEBHOOK_URL`
   - Mark as "Protected" and "Masked"

---

## Testing the Pipeline

### 1. Validate Configuration

```bash
# Clone your repository
git clone <your-repo-url>
cd user-management-service

# Verify .gitlab-ci.yml syntax
docker run --rm -v "$PWD":/builds gitlab/gitlab-runner:latest \
  gitlab-runner exec docker --docker-privileged validate:dependencies
```

### 2. Run Pipeline

```bash
# Commit and push changes
git add .
git commit -m "Add CI/CD pipeline configuration"
git push origin develop
```

### 3. Monitor Pipeline

1. Go to your GitLab project
2. Navigate to **CI/CD > Pipelines**
3. Click on the running pipeline
4. Monitor each stage:
   - ✓ Validate (1-2 min)
   - ✓ Build (2-3 min)
   - ✓ Test (5-10 min)
   - ✓ Analyze (3-5 min)
   - ✓ Security (5-7 min)
   - ✓ Package (3-5 min)
   - ✓ Deploy (3-5 min)
   - ✓ Smoke Test (1-2 min)
   - ✓ Notify (< 1 min)

---

## Troubleshooting

### Common Issues

#### 1. Maven Build Failures

**Error:** `Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin`

**Solution:**
- Verify Java version in `pom.xml` matches Docker image (Java 17)
- Check for syntax errors in Java code
- Clear Maven cache: `mvn clean`

#### 2. Docker Build Failures

**Error:** `unauthorized: authentication required`

**Solution:**
```bash
# Verify registry credentials
docker login registry.gitlab.com -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD
```

#### 3. GKE Deployment Failures

**Error:** `ERROR: (gcloud.container.clusters.get-credentials) ResponseError: code=403`

**Solution:**
- Verify service account has correct permissions
- Re-encode service account key:
  ```bash
  cat key.json | base64 -w 0 > key-base64.txt
  ```

#### 4. PostgreSQL Connection Failures

**Error:** `Connection refused: postgres:5432`

**Solution:**
- Verify `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD` are set correctly
- Check network connectivity from GKE to database
- Verify database accepts connections from GKE cluster IP range

#### 5. Redis Connection Failures

**Error:** `Unable to connect to Redis`

**Solution:**
- Verify `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`
- Check Redis is accessible from GKE cluster
- Test connectivity: `redis-cli -h ${REDIS_HOST} -a ${REDIS_PASSWORD} PING`

#### 6. Smoke Tests Failing

**Error:** `curl: (7) Failed to connect to service`

**Solution:**
- Increase sleep time in smoke test stage (currently 30s)
- Verify `DEPLOYMENT_URL` is correctly set
- Check Kubernetes service is created: `kubectl get svc -n development`

#### 7. SonarCloud Analysis Failures

**Error:** `Not authorized. Please check the properties sonar.token`

**Solution:**
- Regenerate SonarCloud token
- Update `SONAR_TOKEN` in GitLab CI/CD variables
- Verify `SONAR_PROJECT_KEY` and `SONAR_ORGANIZATION` are correct

---

## Pipeline Optimization Tips

### 1. Cache Optimization
The pipeline uses Maven repository caching. To improve:

```yaml
cache:
  key:
    files:
      - pom.xml
      - package-lock.json  # If using npm
  paths:
    - .m2/repository
    - node_modules/  # If using npm
```

### 2. Parallel Execution
Tests run in parallel by default. For more parallelization:

```yaml
test:unit:
  parallel: 3  # Run 3 instances in parallel
```

### 3. Resource Allocation
For faster builds, increase runner resources:

```yaml
variables:
  MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository -Xmx2048m"
```

---

## Security Best Practices

1. **Never commit secrets** to the repository
2. **Use masked variables** for all sensitive data
3. **Rotate secrets regularly** (quarterly recommended)
4. **Enable branch protection** for main/develop branches
5. **Require approvals** before deployment to production
6. **Use separate service accounts** for each environment
7. **Enable audit logging** in GCP and GitLab
8. **Review security scan reports** in every pipeline run

---

## Support and Resources

### Documentation
- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)

### Additional Help
- Create an issue in your repository
- Contact your DevOps team
- Review pipeline logs in GitLab CI/CD interface

---

## Appendix: Quick Reference Commands

### GitLab CLI Commands

```bash
# View pipeline status
gitlab-ci-lint < .gitlab-ci.yml

# Trigger manual pipeline
curl -X POST \
  --form token=<token> \
  --form ref=develop \
  https://gitlab.com/api/v4/projects/<project-id>/trigger/pipeline
```

### Kubernetes Commands

```bash
# View deployment status
kubectl get deployments -n development

# View pod logs
kubectl logs -f -l app=user-management-service -n development

# Restart deployment
kubectl rollout restart deployment/user-management-service -n development

# View secrets
kubectl get secrets -n development

# Describe pod
kubectl describe pod <pod-name> -n development
```

### Maven Commands

```bash
# Run tests locally
mvn clean test

# Run integration tests
mvn verify -DskipUnitTests

# Generate coverage report
mvn jacoco:report

# Run security check
mvn org.owasp:dependency-check-maven:check
```

---

**Document Version:** 1.0
**Last Updated:** January 2025
**Maintained by:** DevOps Team
