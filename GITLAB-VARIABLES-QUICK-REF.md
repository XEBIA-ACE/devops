# GitLab CI/CD Variables - Quick Reference
## User Management Service (SVC-001)

Use this checklist when setting up CI/CD variables in GitLab.

**Location:** Settings > CI/CD > Variables

---

## Variables Checklist

### Database (PostgreSQL) - 5 variables
- [ ] `DB_HOST` - Protected ✓, Masked ✗
- [ ] `DB_PORT` - Protected ✓, Masked ✗
- [ ] `DB_NAME` - Protected ✓, Masked ✗
- [ ] `DB_USERNAME` - Protected ✓, Masked ✗
- [ ] `DB_PASSWORD` - Protected ✓, Masked ✓

### Redis Cache - 3 variables
- [ ] `REDIS_HOST` - Protected ✓, Masked ✗
- [ ] `REDIS_PORT` - Protected ✓, Masked ✗
- [ ] `REDIS_PASSWORD` - Protected ✓, Masked ✓

### Event Bus - 4 variables
- [ ] `EVENT_BUS_HOST` - Protected ✓, Masked ✗
- [ ] `EVENT_BUS_PORT` - Protected ✓, Masked ✗
- [ ] `EVENT_BUS_USERNAME` - Protected ✓, Masked ✗
- [ ] `EVENT_BUS_PASSWORD` - Protected ✓, Masked ✓

### Security & Auth - 2 variables
- [ ] `JWT_SECRET` - Protected ✓, Masked ✓ (min 32 chars)
- [ ] `OAUTH_CLIENT_SECRET` - Protected ✓, Masked ✓

### GKE Configuration - 4 variables
- [ ] `GKE_SERVICE_ACCOUNT_KEY` - Protected ✓, Masked ✓ (Type: File, base64-encoded)
- [ ] `GCP_PROJECT_ID` - Protected ✓, Masked ✗
- [ ] `GKE_CLUSTER_NAME` - Protected ✓, Masked ✗
- [ ] `GKE_REGION` - Protected ✓, Masked ✗

### Security Scanning - SonarCloud - 3 variables
- [ ] `SONAR_TOKEN` - Protected ✓, Masked ✓
- [ ] `SONAR_PROJECT_KEY` - Protected ✗, Masked ✗
- [ ] `SONAR_ORGANIZATION` - Protected ✗, Masked ✗

### Security Scanning - Snyk - 2 variables
- [ ] `SNYK_TOKEN` - Protected ✓, Masked ✓
- [ ] `SNYK_ORG_ID` - Protected ✗, Masked ✗

### Notifications - 2 variables
- [ ] `SLACK_WEBHOOK_URL` - Protected ✗, Masked ✓
- [ ] `NOTIFICATION_EMAIL` - Protected ✗, Masked ✗

### Deployment - 1 variable
- [ ] `DEPLOYMENT_URL` - Protected ✓, Masked ✗

---

## Total: 26 Variables Required

### Critical (Pipeline will fail without these): 15
- All Database variables (5)
- All Redis variables (3)
- JWT_SECRET (1)
- All GKE variables (4)
- DEPLOYMENT_URL (1)
- OAUTH_CLIENT_SECRET (1)

### Optional (Features will be degraded): 11
- Event Bus variables (4) - pipeline continues if checks fail
- SonarCloud variables (3) - job marked as `allow_failure: true`
- Snyk variables (2) - job marked as `allow_failure: true`
- Notification variables (2) - job marked as `allow_failure: true`

---

## Quick Setup Commands

### Export variables from environment
```bash
# Database
export DB_HOST="postgres.example.com"
export DB_PORT="5432"
export DB_NAME="userservice_prod"
export DB_USERNAME="userservice_app"
export DB_PASSWORD="YOUR_SECURE_PASSWORD"

# Redis
export REDIS_HOST="redis.example.com"
export REDIS_PORT="6379"
export REDIS_PASSWORD="YOUR_REDIS_PASSWORD"

# Event Bus
export EVENT_BUS_HOST="kafka.example.com"
export EVENT_BUS_PORT="9092"
export EVENT_BUS_USERNAME="userservice"
export EVENT_BUS_PASSWORD="YOUR_EVENTBUS_PASSWORD"

# Security
export JWT_SECRET="YOUR_JWT_SECRET_MIN_32_CHARACTERS"
export OAUTH_CLIENT_SECRET="YOUR_OAUTH_CLIENT_SECRET"

# GKE
export GCP_PROJECT_ID="your-gcp-project"
export GKE_CLUSTER_NAME="your-cluster-name"
export GKE_REGION="us-central1"
export GKE_SERVICE_ACCOUNT_KEY="$(cat gke-key.json | base64 -w 0)"

# Deployment
export DEPLOYMENT_URL="https://dev.user-management.example.com"
```

### Add to GitLab via API (optional)
```bash
#!/bin/bash
PROJECT_ID="your-gitlab-project-id"
GITLAB_TOKEN="your-personal-access-token"
GITLAB_URL="https://gitlab.com"

# Function to add variable
add_variable() {
  local key=$1
  local value=$2
  local protected=$3
  local masked=$4

  curl --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/variables" \
    --form "key=${key}" \
    --form "value=${value}" \
    --form "protected=${protected}" \
    --form "masked=${masked}"
}

# Example usage
add_variable "DB_HOST" "${DB_HOST}" "true" "false"
add_variable "DB_PASSWORD" "${DB_PASSWORD}" "true" "true"
# ... repeat for all variables
```

---

## Validation Script

Save as `validate-gitlab-vars.sh`:

```bash
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Required variables
REQUIRED_VARS=(
  "DB_HOST"
  "DB_PORT"
  "DB_NAME"
  "DB_USERNAME"
  "DB_PASSWORD"
  "REDIS_HOST"
  "REDIS_PORT"
  "REDIS_PASSWORD"
  "JWT_SECRET"
  "OAUTH_CLIENT_SECRET"
  "GKE_SERVICE_ACCOUNT_KEY"
  "GCP_PROJECT_ID"
  "GKE_CLUSTER_NAME"
  "GKE_REGION"
  "DEPLOYMENT_URL"
)

echo "Validating GitLab CI/CD Variables..."
echo "======================================"

MISSING_COUNT=0

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo -e "${RED}✗${NC} Missing: $var"
    ((MISSING_COUNT++))
  else
    echo -e "${GREEN}✓${NC} Found: $var"
  fi
done

echo ""
echo "======================================"

if [ $MISSING_COUNT -eq 0 ]; then
  echo -e "${GREEN}All required variables are set!${NC}"
  exit 0
else
  echo -e "${RED}Missing $MISSING_COUNT required variable(s)${NC}"
  exit 1
fi
```

Run with:
```bash
chmod +x validate-gitlab-vars.sh
./validate-gitlab-vars.sh
```

---

## Security Notes

1. **Never commit secrets to Git**
   - Use `.gitignore` for local env files
   - Use GitLab masked variables for sensitive data

2. **Masked variables requirements**
   - Must be at least 8 characters
   - Cannot contain whitespace
   - Gitlab will hide these in logs

3. **Protected variables**
   - Only available on protected branches (main, develop)
   - Required for production secrets

4. **File-type variables**
   - Use for certificates and keys
   - Must be base64-encoded for `GKE_SERVICE_ACCOUNT_KEY`

---

## Troubleshooting

### "Variable not found" error
- Check variable key spelling (case-sensitive)
- Verify variable is not protected (if running on feature branch)
- Check variable scope (project vs. group)

### "Masked variable contains invalid characters"
- Remove spaces from the value
- Ensure value is at least 8 characters
- Use base64 encoding if needed

### GKE authentication fails
```bash
# Test base64 encoding
echo $GKE_SERVICE_ACCOUNT_KEY | base64 -d | jq .
# Should output valid JSON
```

---

**Last Updated:** 2026-01-12
