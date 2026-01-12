# User Management Service (SVC-001) - CI/CD Setup Guide

## Overview

This guide provides complete instructions for configuring the GitLab CI/CD pipeline for the **User Management Service** (SVC-001). The pipeline is designed for production-grade deployments to Google Kubernetes Engine (GKE) with comprehensive testing, security scanning, and smoke testing.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [GitLab CI/CD Variables Configuration](#gitlab-cicd-variables-configuration)
3. [Kubernetes Secrets Setup](#kubernetes-secrets-setup)
4. [Docker Registry Configuration](#docker-registry-configuration)
5. [GKE Cluster Preparation](#gke-cluster-preparation)
6. [Verification Steps](#verification-steps)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before setting up the pipeline, ensure you have:

- **GitLab Account** with appropriate permissions (Maintainer or Owner role)
- **Google Cloud Platform (GCP) Account** with billing enabled
- **GKE Cluster** provisioned and accessible
- **GitLab Runner** configured with Docker executor
- **kubectl** CLI tool installed locally
- **gcloud** CLI tool installed and configured

---

## GitLab CI/CD Variables Configuration

Navigate to your GitLab project: **Settings → CI/CD → Variables**

### 1. Service Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `SERVICE_ID` | Variable | `SVC-001` | No | No | Unique service identifier |
| `SERVICE_NAME` | Variable | `user-management-service` | No | No | Service name for deployments |

### 2. Google Cloud & GKE Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `GCP_PROJECT_ID` | Variable | `my-project-12345` | Yes | No | Your GCP project ID |
| `GKE_SERVICE_ACCOUNT_KEY` | File | *JSON key content (base64 encoded)* | Yes | Yes | Service account key for GKE access |
| `GKE_CLUSTER_NAME` | Variable | `production-gke-cluster` | Yes | No | Name of your GKE cluster |
| `GKE_REGION` | Variable | `us-central1` | Yes | No | GCP region where cluster is located |
| `GKE_CLUSTER_ZONE` | Variable | `us-central1-a` | Yes | No | GCP zone (if zonal cluster) |

#### How to Create GKE Service Account Key:

```bash
# 1. Create a service account
gcloud iam service-accounts create gitlab-ci-deployer \
  --display-name="GitLab CI Deployer" \
  --project=YOUR_PROJECT_ID

# 2. Grant necessary permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# 3. Create and download the key
gcloud iam service-accounts keys create key.json \
  --iam-account=gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

# 4. Base64 encode the key (for GitLab variable)
cat key.json | base64 -w 0 > key-base64.txt

# 5. Copy the content of key-base64.txt to GKE_SERVICE_ACCOUNT_KEY variable
```

### 3. PostgreSQL Database Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `DB_HOST` | Variable | `postgres.default.svc.cluster.local` | Yes | No | PostgreSQL hostname/service name |
| `DB_PORT` | Variable | `5432` | Yes | No | PostgreSQL port |
| `DB_NAME` | Variable | `userservice_db` | Yes | No | Database name |
| `DB_USERNAME` | Variable | `userservice_app` | Yes | Yes | Database username |
| `DB_PASSWORD` | Variable | `SecureP@ssw0rd123!` | Yes | Yes | Database password |
| `POSTGRES_HOST` | Variable | `postgres.default.svc.cluster.local` | Yes | No | Alias for DB_HOST (used in pre-checks) |
| `POSTGRES_PORT` | Variable | `5432` | Yes | No | Alias for DB_PORT |

### 4. Redis Cache Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `REDIS_HOST` | Variable | `redis.default.svc.cluster.local` | Yes | No | Redis hostname/service name |
| `REDIS_PORT` | Variable | `6379` | Yes | No | Redis port |
| `REDIS_PASSWORD` | Variable | `RedisSecurePass123!` | Yes | Yes | Redis password (if authentication enabled) |

### 5. Event Bus Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `EVENT_BUS_HOST` | Variable | `rabbitmq.default.svc.cluster.local` | Yes | No | Event bus hostname (RabbitMQ/Kafka) |
| `EVENT_BUS_PORT` | Variable | `5672` | Yes | No | Event bus port |
| `EVENT_BUS_USERNAME` | Variable | `eventbus_user` | Yes | Yes | Event bus username |
| `EVENT_BUS_PASSWORD` | Variable | `EventBusPass123!` | Yes | Yes | Event bus password |

### 6. JWT & OAuth Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `JWT_SECRET` | Variable | *Long random string* | Yes | Yes | Secret key for JWT token signing |
| `JWT_EXPIRATION` | Variable | `3600000` | Yes | No | JWT expiration time (milliseconds) |
| `OAUTH_CLIENT_ID` | Variable | `user-mgmt-client-id` | Yes | Yes | OAuth 2.0 client ID |
| `OAUTH_CLIENT_SECRET` | Variable | *OAuth client secret* | Yes | Yes | OAuth 2.0 client secret |

#### Generate JWT Secret:

```bash
# Generate a secure random JWT secret
openssl rand -base64 64
```

### 7. Security Scanning Configuration

#### SonarCloud

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `SONAR_TOKEN` | Variable | *Your SonarCloud token* | Yes | Yes | SonarCloud authentication token |
| `SONAR_PROJECT_KEY` | Variable | `your-org_user-management-service` | No | No | SonarCloud project key |
| `SONAR_ORGANIZATION` | Variable | `your-organization` | No | No | SonarCloud organization |
| `SONAR_HOST_URL` | Variable | `https://sonarcloud.io` | No | No | SonarCloud URL |

**How to get SonarCloud credentials:**
1. Go to [SonarCloud.io](https://sonarcloud.io)
2. Create/import your project
3. Generate token: **My Account → Security → Generate Tokens**
4. Copy Organization and Project Key from project settings

#### Snyk

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `SNYK_TOKEN` | Variable | *Your Snyk API token* | Yes | Yes | Snyk authentication token |
| `SNYK_ORG_ID` | Variable | `your-org-id` | No | No | Snyk organization ID |

**How to get Snyk credentials:**
1. Sign up at [Snyk.io](https://snyk.io)
2. Go to **Account Settings → General**
3. Copy your API token
4. Get Organization ID from organization settings

### 8. Deployment Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `KUBE_NAMESPACE` | Variable | `user-management` | Yes | No | Kubernetes namespace for deployments |
| `DEPLOYMENT_URL` | Variable | `https://dev.user-mgmt.company.com` | No | No | Base URL for smoke tests |
| `ENVIRONMENT` | Variable | `development` | No | No | Environment name (development/staging/production) |

### 9. Notification Configuration

| Variable | Type | Value Example | Protected | Masked | Description |
|----------|------|---------------|-----------|--------|-------------|
| `SLACK_WEBHOOK_URL` | Variable | `https://hooks.slack.com/services/...` | Yes | Yes | Slack incoming webhook URL |
| `NOTIFICATION_EMAIL` | Variable | `devops-team@company.com` | No | No | Email for failure notifications |

**How to create Slack webhook:**
1. Go to your Slack workspace
2. Create an Incoming Webhook app
3. Select the channel for notifications
4. Copy the webhook URL

---

## Kubernetes Secrets Setup

The pipeline automatically creates Kubernetes secrets during deployment, but you can manually create them:

### 1. Create Namespace

```bash
kubectl create namespace user-management
```

### 2. Create PostgreSQL Secret

```bash
kubectl create secret generic postgres-credentials \
  --from-literal=username=userservice_app \
  --from-literal=password='SecureP@ssw0rd123!' \
  --namespace=user-management
```

### 3. Create Redis Secret

```bash
kubectl create secret generic redis-credentials \
  --from-literal=password='RedisSecurePass123!' \
  --namespace=user-management
```

### 4. Create Event Bus Secret

```bash
kubectl create secret generic event-bus-credentials \
  --from-literal=username=eventbus_user \
  --from-literal=password='EventBusPass123!' \
  --namespace=user-management
```

### 5. Create JWT Secret

```bash
kubectl create secret generic jwt-credentials \
  --from-literal=secret='YOUR_GENERATED_JWT_SECRET' \
  --namespace=user-management
```

### 6. Create OAuth2 Secret

```bash
kubectl create secret generic oauth2-credentials \
  --from-literal=client-id='user-mgmt-client-id' \
  --from-literal=client-secret='YOUR_OAUTH_CLIENT_SECRET' \
  --namespace=user-management
```

### 7. Create GitLab Registry Credentials

```bash
kubectl create secret docker-registry gitlab-registry-credentials \
  --docker-server=registry.gitlab.com \
  --docker-username=YOUR_GITLAB_USERNAME \
  --docker-password=YOUR_GITLAB_ACCESS_TOKEN \
  --docker-email=YOUR_EMAIL \
  --namespace=user-management
```

### 8. Create Service Account

```bash
kubectl create serviceaccount user-management-service-sa \
  --namespace=user-management

# Grant necessary permissions
kubectl create rolebinding user-management-service-rb \
  --clusterrole=edit \
  --serviceaccount=user-management:user-management-service-sa \
  --namespace=user-management
```

---

## Docker Registry Configuration

The pipeline uses GitLab Container Registry by default.

### Enable Container Registry

1. Go to **Settings → CI/CD → Container Registry**
2. Ensure Container Registry is enabled
3. Note the registry URL (usually `registry.gitlab.com/your-group/your-project`)

### Registry Authentication

The pipeline automatically authenticates using:
- `CI_REGISTRY_USER` (predefined by GitLab)
- `CI_REGISTRY_PASSWORD` (predefined by GitLab)
- `CI_REGISTRY` (predefined by GitLab)

---

## GKE Cluster Preparation

### 1. Ensure Required APIs are Enabled

```bash
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

### 2. Configure Cluster Access

```bash
# Get cluster credentials
gcloud container clusters get-credentials YOUR_CLUSTER_NAME \
  --region=YOUR_REGION \
  --project=YOUR_PROJECT_ID

# Verify access
kubectl cluster-info
kubectl get nodes
```

### 3. Deploy Dependencies

#### PostgreSQL Deployment (Example)

```yaml
# postgres-deployment.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: user-management
spec:
  ports:
  - port: 5432
  selector:
    app: postgres
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: user-management
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: userservice_db
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

Apply:
```bash
kubectl apply -f postgres-deployment.yaml
```

#### Redis Deployment (Example)

```yaml
# redis-deployment.yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: user-management
spec:
  ports:
  - port: 6379
  selector:
    app: redis
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: user-management
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        command:
        - redis-server
        - --requirepass
        - $(REDIS_PASSWORD)
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: password
```

Apply:
```bash
kubectl apply -f redis-deployment.yaml
```

---

## Verification Steps

### 1. Test Pipeline Manually

1. Go to **CI/CD → Pipelines**
2. Click **Run Pipeline**
3. Select the branch (e.g., `develop`)
4. Monitor the pipeline execution

### 2. Verify Docker Image

```bash
# Login to GitLab registry
docker login registry.gitlab.com

# Pull the image
docker pull registry.gitlab.com/your-group/your-project/user-management-service:latest

# Inspect the image
docker inspect registry.gitlab.com/your-group/your-project/user-management-service:latest
```

### 3. Check Kubernetes Deployment

```bash
# Check pods
kubectl get pods -n user-management

# Check deployment
kubectl get deployment user-management-service -n user-management

# Check service
kubectl get svc user-management-service -n user-management

# View logs
kubectl logs -f deployment/user-management-service -n user-management

# Check pod health
kubectl describe pod <pod-name> -n user-management
```

### 4. Test API Endpoints

```bash
# Get service endpoint
kubectl get svc user-management-service -n user-management

# Test health endpoint
curl https://your-service-url/actuator/health

# Test API endpoints (smoke test)
curl -X POST https://your-service-url/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"Test123!"}'
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. **GKE Authentication Failure**

**Error:** `ERROR: (gcloud.container.clusters.get-credentials) ResponseError: code=403`

**Solution:**
- Verify service account has correct permissions
- Check if `GKE_SERVICE_ACCOUNT_KEY` is correctly base64 encoded
- Ensure the key is valid and not expired

```bash
# Test authentication locally
echo "$GKE_SERVICE_ACCOUNT_KEY" | base64 -d > /tmp/key.json
gcloud auth activate-service-account --key-file=/tmp/key.json
```

#### 2. **Dependency Check Failures**

**Error:** `PostgreSQL Database is not reachable!`

**Solution:**
- Verify PostgreSQL is deployed and running
- Check service name and namespace are correct
- Ensure network policies allow connectivity

```bash
# Test connectivity from within cluster
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never \
  --namespace=user-management -- \
  psql -h postgres.user-management.svc.cluster.local -U userservice_app -d userservice_db
```

#### 3. **Docker Build Failures**

**Error:** `Cannot find JAR file`

**Solution:**
- Ensure `build:compile` and `package:jar` stages completed successfully
- Check artifact dependencies in pipeline configuration
- Verify Maven build produces JAR file

```bash
# Test Maven build locally
mvn clean package -DskipTests
ls -la target/*.jar
```

#### 4. **Snyk/SonarCloud Failures**

**Error:** `Authentication failed`

**Solution:**
- Verify tokens are correct and not expired
- Check organization IDs and project keys
- Ensure services are accessible (not blocked by firewall)

```bash
# Test Snyk authentication
snyk auth $SNYK_TOKEN
snyk test

# Test SonarCloud connectivity
curl -u ${SONAR_TOKEN}: https://sonarcloud.io/api/authentication/validate
```

#### 5. **Smoke Test Failures**

**Error:** `curl: (28) Connection timed out`

**Solution:**
- Increase wait time before smoke tests (modify sleep duration)
- Verify service is accessible from runner
- Check ingress/load balancer configuration
- Ensure firewall rules allow traffic

```bash
# Check if service is ready
kubectl get pods -n user-management -l app=user-management-service
kubectl logs -f deployment/user-management-service -n user-management

# Test from within cluster
kubectl run -it --rm curl --image=curlimages/curl --restart=Never \
  --namespace=user-management -- \
  curl http://user-management-service/actuator/health
```

#### 6. **Secret Creation Errors**

**Error:** `secrets already exists`

**Solution:**
- Pipeline creates secrets idempotently using `--dry-run=client -o yaml | kubectl apply -f -`
- To manually update: `kubectl delete secret <secret-name> -n user-management`
- Then recreate the secret

#### 7. **Rollout Timeout**

**Error:** `error: timed out waiting for the condition`

**Solution:**
- Check pod logs: `kubectl logs -f deployment/user-management-service -n user-management`
- Describe pod: `kubectl describe pod <pod-name> -n user-management`
- Common causes:
  - Image pull errors (check registry credentials)
  - Resource limits too low
  - Liveness/readiness probes failing
  - Missing environment variables or secrets

---

## Pipeline Stage Details

### Stage Flow

```
validate → build → test → analyze → security → package → deploy → smoke-test → notify
```

### Stage Descriptions

1. **validate**: Validates Maven POM and dependency health
2. **build**: Compiles source code and creates JAR artifact
3. **test**: Runs unit and integration tests with coverage
4. **analyze**: Performs SonarCloud code quality analysis
5. **security**: Scans dependencies and code with Snyk and OWASP
6. **package**: Builds Docker image and scans with Trivy
7. **deploy**: Deploys to GKE with pre-deployment dependency checks
8. **smoke-test**: Validates all API endpoints are reachable
9. **notify**: Sends success/failure notifications to Slack

---

## Best Practices

### Security

1. **Always use masked variables** for sensitive data (passwords, tokens)
2. **Protect production variables** to prevent exposure in non-protected branches
3. **Rotate secrets regularly** (JWT secrets, database passwords)
4. **Use Kubernetes secrets** for runtime credentials
5. **Enable RBAC** on GKE cluster with least-privilege principle

### Performance

1. **Enable caching** for Maven dependencies (already configured)
2. **Use parallel jobs** where possible (tests run in parallel)
3. **Optimize Docker layers** using multi-stage builds
4. **Use specific image tags** instead of `latest` in production

### Reliability

1. **Set appropriate timeouts** for deployment rollouts
2. **Configure health checks** properly (liveness, readiness, startup probes)
3. **Use HPA (Horizontal Pod Autoscaler)** for production workloads
4. **Monitor pipeline execution** and set up alerting
5. **Test rollback procedures** regularly

---

## Additional Resources

- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [Google Kubernetes Engine Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html)
- [SonarCloud Documentation](https://docs.sonarcloud.io/)
- [Snyk Documentation](https://docs.snyk.io/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)

---

## Support and Contact

For issues or questions:
- **Email:** devops-team@company.com
- **Slack:** #devops-support
- **Issue Tracker:** GitLab Issues in this repository

---

**Last Updated:** 2026-01-12
**Version:** 1.0.0
**Maintained By:** DevOps Engineering Team
