# GitLab CI/CD Variables - Quick Reference

## User Management Service (SVC-001)

This is a condensed reference for all required GitLab CI/CD variables. For detailed setup instructions, see [SETUP-GUIDE-COMPLETE.md](./SETUP-GUIDE-COMPLETE.md).

---

## Quick Setup Checklist

- [ ] Configure GCP & GKE variables
- [ ] Set up PostgreSQL credentials
- [ ] Set up Redis credentials
- [ ] Set up Event Bus credentials
- [ ] Configure JWT & OAuth secrets
- [ ] Set up SonarCloud integration
- [ ] Set up Snyk integration
- [ ] Configure notification endpoints
- [ ] Create Kubernetes secrets
- [ ] Test pipeline

---

## Variable Summary Table

### Legend
- **P**: Protected (✓ = Yes, - = No)
- **M**: Masked (✓ = Yes, - = No)
- **R**: Required (✓ = Required, ~ = Optional)

| Category | Variable Name | Type | P | M | R | Example Value |
|----------|---------------|------|---|---|---|---------------|
| **GCP & Kubernetes** |||||
|| `GCP_PROJECT_ID` | Variable | ✓ | - | ✓ | `my-project-12345` |
|| `GKE_SERVICE_ACCOUNT_KEY` | File | ✓ | ✓ | ✓ | *base64-encoded JSON* |
|| `GKE_CLUSTER_NAME` | Variable | ✓ | - | ✓ | `production-cluster` |
|| `GKE_REGION` | Variable | ✓ | - | ✓ | `us-central1` |
|| `GKE_CLUSTER_ZONE` | Variable | ✓ | - | ~ | `us-central1-a` |
|| `KUBE_NAMESPACE` | Variable | ✓ | - | ✓ | `user-management` |
| **PostgreSQL** |||||
|| `DB_HOST` / `POSTGRES_HOST` | Variable | ✓ | - | ✓ | `postgres.default.svc.cluster.local` |
|| `DB_PORT` / `POSTGRES_PORT` | Variable | ✓ | - | ✓ | `5432` |
|| `DB_NAME` | Variable | ✓ | - | ✓ | `userservice_db` |
|| `DB_USERNAME` | Variable | ✓ | ✓ | ✓ | `userservice_app` |
|| `DB_PASSWORD` | Variable | ✓ | ✓ | ✓ | *secure password* |
| **Redis** |||||
|| `REDIS_HOST` | Variable | ✓ | - | ✓ | `redis.default.svc.cluster.local` |
|| `REDIS_PORT` | Variable | ✓ | - | ✓ | `6379` |
|| `REDIS_PASSWORD` | Variable | ✓ | ✓ | ~ | *secure password* |
| **Event Bus** |||||
|| `EVENT_BUS_HOST` | Variable | ✓ | - | ✓ | `rabbitmq.default.svc.cluster.local` |
|| `EVENT_BUS_PORT` | Variable | ✓ | - | ✓ | `5672` |
|| `EVENT_BUS_USERNAME` | Variable | ✓ | ✓ | ✓ | `eventbus_user` |
|| `EVENT_BUS_PASSWORD` | Variable | ✓ | ✓ | ✓ | *secure password* |
| **JWT & OAuth** |||||
|| `JWT_SECRET` | Variable | ✓ | ✓ | ✓ | *64-char random string* |
|| `JWT_EXPIRATION` | Variable | ✓ | - | ~ | `3600000` |
|| `OAUTH_CLIENT_ID` | Variable | ✓ | ✓ | ✓ | `user-mgmt-client-id` |
|| `OAUTH_CLIENT_SECRET` | Variable | ✓ | ✓ | ✓ | *OAuth secret* |
| **SonarCloud** |||||
|| `SONAR_TOKEN` | Variable | ✓ | ✓ | ✓ | *SonarCloud token* |
|| `SONAR_PROJECT_KEY` | Variable | - | - | ✓ | `your-org_user-mgmt-service` |
|| `SONAR_ORGANIZATION` | Variable | - | - | ✓ | `your-organization` |
|| `SONAR_HOST_URL` | Variable | - | - | ~ | `https://sonarcloud.io` |
| **Snyk** |||||
|| `SNYK_TOKEN` | Variable | ✓ | ✓ | ✓ | *Snyk API token* |
|| `SNYK_ORG_ID` | Variable | - | - | ✓ | `your-org-id` |
| **Deployment** |||||
|| `DEPLOYMENT_URL` | Variable | - | - | ✓ | `https://dev.user-mgmt.example.com` |
|| `ENVIRONMENT` | Variable | - | - | ~ | `development` |
| **Notifications** |||||
|| `SLACK_WEBHOOK_URL` | Variable | ✓ | ✓ | ~ | `https://hooks.slack.com/services/...` |
|| `NOTIFICATION_EMAIL` | Variable | - | - | ~ | `devops@company.com` |

---

## Copy-Paste Templates

### 1. Generate JWT Secret

```bash
# Generate secure JWT secret (copy the output)
openssl rand -base64 64
```

### 2. Create GKE Service Account

```bash
# Replace YOUR_PROJECT_ID with your actual project ID

# Create service account
gcloud iam service-accounts create gitlab-ci-deployer \
  --display-name="GitLab CI Deployer" \
  --project=YOUR_PROJECT_ID

# Grant permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Create key
gcloud iam service-accounts keys create key.json \
  --iam-account=gitlab-ci-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Base64 encode
cat key.json | base64 -w 0 > key-base64.txt

# Copy content of key-base64.txt to GitLab variable GKE_SERVICE_ACCOUNT_KEY
```

### 3. Create Kubernetes Secrets (All-in-One)

```bash
# Set your namespace
NAMESPACE=user-management

# Create namespace
kubectl create namespace $NAMESPACE

# PostgreSQL
kubectl create secret generic postgres-credentials \
  --from-literal=username=userservice_app \
  --from-literal=password='YOUR_DB_PASSWORD' \
  --namespace=$NAMESPACE

# Redis
kubectl create secret generic redis-credentials \
  --from-literal=password='YOUR_REDIS_PASSWORD' \
  --namespace=$NAMESPACE

# Event Bus
kubectl create secret generic event-bus-credentials \
  --from-literal=username=eventbus_user \
  --from-literal=password='YOUR_EVENTBUS_PASSWORD' \
  --namespace=$NAMESPACE

# JWT
kubectl create secret generic jwt-credentials \
  --from-literal=secret='YOUR_JWT_SECRET' \
  --namespace=$NAMESPACE

# OAuth2
kubectl create secret generic oauth2-credentials \
  --from-literal=client-id='user-mgmt-client-id' \
  --from-literal=client-secret='YOUR_OAUTH_SECRET' \
  --namespace=$NAMESPACE

# GitLab Registry
kubectl create secret docker-registry gitlab-registry-credentials \
  --docker-server=registry.gitlab.com \
  --docker-username=YOUR_GITLAB_USERNAME \
  --docker-password=YOUR_GITLAB_TOKEN \
  --docker-email=YOUR_EMAIL \
  --namespace=$NAMESPACE

# Service Account
kubectl create serviceaccount user-management-service-sa \
  --namespace=$NAMESPACE

kubectl create rolebinding user-management-service-rb \
  --clusterrole=edit \
  --serviceaccount=$NAMESPACE:user-management-service-sa \
  --namespace=$NAMESPACE
```

### 4. Verify Kubernetes Secrets

```bash
# List all secrets
kubectl get secrets -n user-management

# Check specific secret
kubectl describe secret postgres-credentials -n user-management

# Decode secret value (for verification)
kubectl get secret postgres-credentials -n user-management -o jsonpath='{.data.username}' | base64 -d
```

---

## Environment-Specific Variables

If you need different values per environment, create environment-scoped variables in GitLab:

### Development Environment

| Variable | Scope | Value |
|----------|-------|-------|
| `DEPLOYMENT_URL` | development | `https://dev.user-mgmt.company.com` |
| `KUBE_NAMESPACE` | development | `user-management-dev` |
| `ENVIRONMENT` | development | `development` |

### Staging Environment

| Variable | Scope | Value |
|----------|-------|-------|
| `DEPLOYMENT_URL` | staging | `https://staging.user-mgmt.company.com` |
| `KUBE_NAMESPACE` | staging | `user-management-staging` |
| `ENVIRONMENT` | staging | `staging` |

### Production Environment

| Variable | Scope | Value |
|----------|-------|-------|
| `DEPLOYMENT_URL` | production | `https://user-mgmt.company.com` |
| `KUBE_NAMESPACE` | production | `user-management-prod` |
| `ENVIRONMENT` | production | `production` |

---

## Validation Commands

Run these commands to verify your setup:

```bash
# 1. Test GCP authentication
echo "$GKE_SERVICE_ACCOUNT_KEY" | base64 -d > /tmp/key.json
gcloud auth activate-service-account --key-file=/tmp/key.json
gcloud container clusters list --project=$GCP_PROJECT_ID

# 2. Test kubectl access
gcloud container clusters get-credentials $GKE_CLUSTER_NAME \
  --region=$GKE_REGION \
  --project=$GCP_PROJECT_ID
kubectl get nodes

# 3. Test PostgreSQL connectivity from cluster
kubectl run -it --rm pg-test --image=postgres:15-alpine --restart=Never \
  --namespace=$KUBE_NAMESPACE -- \
  psql -h $POSTGRES_HOST -U $DB_USERNAME -d $DB_NAME -c "SELECT 1"

# 4. Test Redis connectivity
kubectl run -it --rm redis-test --image=redis:7-alpine --restart=Never \
  --namespace=$KUBE_NAMESPACE -- \
  redis-cli -h $REDIS_HOST -p $REDIS_PORT PING

# 5. Test Snyk authentication
snyk auth $SNYK_TOKEN
snyk test --file=pom.xml

# 6. Test SonarCloud authentication
curl -u ${SONAR_TOKEN}: https://sonarcloud.io/api/authentication/validate
```

---

## Common Variable Combinations

### For Local Testing

```bash
# .env file for local development
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=userservice_local
export DB_USERNAME=localuser
export DB_PASSWORD=localpass

export REDIS_HOST=localhost
export REDIS_PORT=6379
export REDIS_PASSWORD=

export JWT_SECRET=$(openssl rand -base64 64)
export JWT_EXPIRATION=3600000

export OAUTH_CLIENT_ID=local-client-id
export OAUTH_CLIENT_SECRET=local-client-secret
```

### For CI Pipeline

All variables should be set in GitLab CI/CD settings as shown in the main table above.

---

## Troubleshooting Variables

### Check if Variable is Set

```bash
# In pipeline script
echo "Checking if variable is set..."
if [ -z "$DB_HOST" ]; then
  echo "ERROR: DB_HOST is not set!"
  exit 1
fi
echo "DB_HOST is set to: $DB_HOST"
```

### Debug Variable Values (Non-Sensitive Only)

```yaml
# Add to .gitlab-ci.yml for debugging
debug:variables:
  stage: validate
  script:
    - echo "GCP_PROJECT_ID=$GCP_PROJECT_ID"
    - echo "GKE_CLUSTER_NAME=$GKE_CLUSTER_NAME"
    - echo "DB_HOST=$DB_HOST"
    - echo "DB_PORT=$DB_PORT"
    # DO NOT echo sensitive variables (passwords, tokens, secrets)
  only:
    - branches
  when: manual
```

---

## Security Checklist

Before going to production, verify:

- [ ] All passwords use strong, randomly generated values
- [ ] All sensitive variables are marked as **Masked**
- [ ] Production variables are marked as **Protected**
- [ ] Secrets are stored in Kubernetes, not in code
- [ ] Service accounts follow least-privilege principle
- [ ] JWT secret is at least 64 characters
- [ ] Database credentials are unique per environment
- [ ] OAuth secrets are not shared between environments
- [ ] Slack webhooks point to correct channels
- [ ] No secrets are committed to Git repository
- [ ] Access to GitLab variables is restricted

---

## Quick Links

- [Complete Setup Guide](./SETUP-GUIDE-COMPLETE.md) - Detailed instructions
- [Pipeline YAML](./.gitlab-ci.yml) - CI/CD configuration
- [GitLab CI/CD Settings](../../-/settings/ci_cd) - Configure variables here

---

**Last Updated:** 2026-01-12
**Version:** 1.0.0
