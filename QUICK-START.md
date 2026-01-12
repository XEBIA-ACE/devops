# Quick Start Guide - GitLab CI/CD Pipeline

## ⚡ 5-Minute Setup

### Step 1: Add Required Variables (2 minutes)

Navigate to **Settings → CI/CD → Variables** and add:

#### Minimum Required Variables

```
# GCP/GKE
GCP_SERVICE_ACCOUNT_KEY    = <base64-encoded-json-key>
GCP_PROJECT_ID             = your-gcp-project-id
GKE_CLUSTER                = your-cluster-name
GKE_ZONE                   = us-central1-a

# SonarCloud
SONAR_TOKEN                = <your-sonar-token>
SONAR_PROJECT_KEY          = your-project-key
SONAR_ORGANIZATION         = your-org-name

# Snyk
SNYK_TOKEN                 = <your-snyk-token>
SNYK_ORG_ID                = <your-snyk-org-id>

# Application Secrets - Staging
DATABASE_URL               = postgresql://user:pass@host:5432/db
REDIS_URL                  = redis://host:6379
JWT_SECRET                 = <generate-random-32-chars>
API_KEY                    = <your-api-key>

# Application Secrets - Production
DATABASE_URL_PROD          = postgresql://user:pass@host:5432/db
REDIS_URL_PROD             = redis://host:6379
JWT_SECRET_PROD            = <generate-random-64-chars>
API_KEY_PROD               = <your-api-key>
```

### Step 2: Update Configuration (1 minute)

Edit `.gitlab-ci.yml`:

```yaml
variables:
  APP_NAME: "your-app-name"  # Change this
```

Edit `k8s/ingress.yaml`:

```yaml
- host: your-domain.com  # Change this
```

### Step 3: Test the Pipeline (2 minutes)

```bash
# Push to trigger pipeline
git add .
git commit -m "feat: setup CI/CD pipeline"
git push origin main

# Watch pipeline in GitLab UI
# Navigate to: CI/CD → Pipelines
```

---

## 🎯 Common Commands

### Generate Secrets

```bash
# JWT Secret
openssl rand -hex 32

# API Key
openssl rand -base64 32

# Base64 encode GCP key
cat gcp-key.json | base64 -w 0
```

### GCP Service Account Setup

```bash
# Create service account
gcloud iam service-accounts create gitlab-ci \
  --display-name="GitLab CI/CD"

# Grant permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:gitlab-ci@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

# Create key
gcloud iam service-accounts keys create key.json \
  --iam-account=gitlab-ci@PROJECT_ID.iam.gserviceaccount.com

# Base64 encode
cat key.json | base64 -w 0
```

### Kubernetes Quick Commands

```bash
# Check deployment
kubectl get pods -n production

# View logs
kubectl logs -f deployment/express-api -n production

# Rollback
kubectl rollout undo deployment/express-api -n production

# Scale manually
kubectl scale deployment/express-api --replicas=5 -n production
```

---

## ✅ Pre-flight Checklist

Before first deployment:

- [ ] All CI/CD variables configured in GitLab
- [ ] GKE cluster is running
- [ ] Databases (PostgreSQL, Redis) are accessible
- [ ] SonarCloud project created
- [ ] Snyk account connected
- [ ] Domain DNS configured (for ingress)
- [ ] SSL certificates configured (cert-manager)
- [ ] Notification webhooks configured (optional)

---

## 🚨 Troubleshooting Quick Fixes

### Pipeline fails immediately
→ Check runner is available: Settings → CI/CD → Runners

### Docker build fails
→ Verify Container Registry enabled: Settings → Packages & Registries

### Tests fail with DB errors
→ Check test DB credentials in test job variables

### Deployment authentication fails
→ Verify GCP_SERVICE_ACCOUNT_KEY is base64-encoded correctly

### Secrets not found in pods
→ Run deploy job again to recreate secrets

---

## 📖 Full Documentation

- **Detailed Setup**: See `CICD-VARIABLES-GUIDE.md`
- **Pipeline Documentation**: See `PIPELINE-README.md`
- **Kubernetes Manifests**: See `k8s/` directory

---

## 🆘 Need Help?

1. Check job logs in GitLab CI/CD → Pipelines
2. Review full guides in repository
3. Contact DevOps team: devops@company.com

---

**Ready to Deploy?** Push to `main` branch and click "Deploy to Production" in the pipeline!
