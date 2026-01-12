# CI/CD Pipeline Architecture - User Management Service (SVC-001)

## Pipeline Overview

This document provides a comprehensive visual overview of the GitLab CI/CD pipeline architecture for the User Management Service.

---

## Pipeline Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GITLAB CI/CD PIPELINE                                 │
│                    User Management Service (SVC-001)                         │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────┐     ┌─────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐
│ VALIDATE  │────▶│  BUILD  │────▶│  TEST   │────▶│ ANALYZE  │────▶│SECURITY │
└───────────┘     └─────────┘     └─────────┘     └──────────┘     └─────────┘
     │                 │                │               │                 │
     ▼                 ▼                ▼               ▼                 ▼
┌─────────┐       ┌─────────┐     ┌──────────┐   ┌──────────┐     ┌──────────┐
│Maven POM│       │Compile  │     │Unit Tests│   │SonarCloud│     │  Snyk    │
│Validate │       │Package  │     │Integration   │Code      │     │  OWASP   │
│Deps     │       │JAR      │     │ Tests    │   │Quality   │     │  Trivy   │
│Health   │       │         │     │          │   │          │     │          │
└─────────┘       └─────────┘     └──────────┘   └──────────┘     └──────────┘

     │                                                                     │
     │                                                                     ▼
     │                                                              ┌──────────┐
     │                                                              │ PACKAGE  │
     │                                                              └──────────┘
     │                                                                     │
     │                                                                     ▼
     │                                                              ┌──────────┐
     │                                                              │Docker    │
     │                                                              │Build     │
     │                                                              │& Push    │
     │                                                              └──────────┘
     │                                                                     │
     └─────────────────────────────────────────────────────────────────────┘
                                                                           │
                                                                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DEPLOY STAGE                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
            ┌───────────┐     ┌──────────┐     ┌──────────┐
            │Pre-Deploy │     │  Deploy  │     │  Deploy  │
            │Dependency │     │   Dev    │     │ Staging  │
            │  Check    │     │ (Manual) │     │ (Manual) │
            └───────────┘     └──────────┘     └──────────┘
                    │                 │                 │
        ┌───────────┼─────────────────┘                 │
        │           │                                   │
        ▼           ▼                                   ▼
    ┌────────┐  ┌────────┐                        ┌────────┐
    │Postgres│  │ Redis  │                        │  GKE   │
    │ Check  │  │ Check  │                        │Cluster │
    └────────┘  └────────┘                        └────────┘
        │           │                                   │
        └───────────┼───────────────────────────────────┘
                    │
                    ▼
            ┌──────────────┐
            │ SMOKE TEST   │
            └──────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
        ▼           ▼           ▼
    ┌────────┐  ┌────────┐  ┌────────┐
    │Auth    │  │Users   │  │Health  │
    │Endpoints  │Endpoints  │Checks  │
    └────────┘  └────────┘  └────────┘
                    │
                    ▼
            ┌──────────────┐
            │   NOTIFY     │
            └──────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
    ┌────────┐            ┌────────┐
    │ Slack  │            │ Email  │
    │Success │            │Failure │
    └────────┘            └────────┘
```

---

## Detailed Stage Breakdown

### Stage 1: VALIDATE (2 jobs)

```
┌─────────────────────────────────────┐
│     VALIDATE STAGE (Parallel)       │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │ validate:maven-pom          │   │
│  ├─────────────────────────────┤   │
│  │ • Maven validate            │   │
│  │ • Dependency tree           │   │
│  │ • Effective POM             │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ validate:dependencies-health│   │
│  ├─────────────────────────────┤   │
│  │ • PostgreSQL reachability   │   │
│  │ • Redis reachability        │   │
│  │ • Event Bus reachability    │   │
│  │ (Allow failure: true)       │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Dependencies Required:**
- PostgreSQL (port 5432)
- Redis (port 6379)
- Event Bus (port 5672/9092)

**Artifacts Produced:**
- build.env (environment variables)

---

### Stage 2: BUILD (2 jobs)

```
┌─────────────────────────────────────┐
│       BUILD STAGE (Sequential)      │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │ build:compile               │   │
│  ├─────────────────────────────┤   │
│  │ • Clean + Compile           │   │
│  │ • Maven cache (pull-push)   │   │
│  │ • Store compiled classes    │   │
│  └─────────────────────────────┘   │
│              │                      │
│              ▼                      │
│  ┌─────────────────────────────┐   │
│  │ build:package               │   │
│  ├─────────────────────────────┤   │
│  │ • Package JAR               │   │
│  │ • Add build metadata        │   │
│  │ • Skip tests (already ran)  │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Artifacts Produced:**
- target/*.jar (Spring Boot application)
- target/build-info.txt (build metadata)

**Cache Strategy:**
```yaml
Cache Key: ${CI_COMMIT_REF_SLUG}-maven-${POM_CHECKSUM}
Paths:
  - .m2/repository (Maven dependencies)
Policy: pull-push
```

---

### Stage 3: TEST (2 jobs in parallel)

```
┌─────────────────────────────────────────────────────────────┐
│              TEST STAGE (Parallel)                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────┐    ┌──────────────────────┐      │
│  │ test:unit            │    │ test:integration     │      │
│  ├──────────────────────┤    ├──────────────────────┤      │
│  │ Services:            │    │ Services:            │      │
│  │ • postgres:15-alpine │    │ • postgres:15-alpine │      │
│  │ • redis:7-alpine     │    │ • redis:7-alpine     │      │
│  │                      │    │                      │      │
│  │ Runs:                │    │ Runs:                │      │
│  │ • Unit tests         │    │ • Integration tests  │      │
│  │ • JaCoCo coverage    │    │ • End-to-end flows   │      │
│  │                      │    │ • API contract tests │      │
│  │ Reports:             │    │                      │      │
│  │ • JUnit XML          │    │ Reports:             │      │
│  │ • Coverage (JaCoCo)  │    │ • JUnit XML          │      │
│  └──────────────────────┘    └──────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Test Coverage:**
- Unit Tests: 70%+ target
- Integration Tests: All API endpoints
- Database: PostgreSQL (Testcontainers)
- Cache: Redis (Session testing)

**Artifacts Produced:**
- target/surefire-reports/TEST-*.xml (JUnit reports)
- target/site/jacoco/jacoco.xml (Coverage report)
- target/failsafe-reports/TEST-*.xml (Integration test reports)

---

### Stage 4: ANALYZE (1 job)

```
┌─────────────────────────────────────┐
│          ANALYZE STAGE              │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │ analyze:sonarcloud          │   │
│  ├─────────────────────────────┤   │
│  │ Analyzes:                   │   │
│  │ • Code quality              │   │
│  │ • Code smells               │   │
│  │ • Security hotspots         │   │
│  │ • Technical debt            │   │
│  │ • Test coverage             │   │
│  │ • Duplications              │   │
│  │                             │   │
│  │ Quality Gate:               │   │
│  │ • Must pass for merge       │   │
│  │ • Configurable thresholds   │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**SonarCloud Metrics:**
- Bugs: 0 tolerance
- Vulnerabilities: 0 tolerance
- Code Smells: < 5% ratio
- Coverage: > 80%
- Duplications: < 3%

---

### Stage 5: SECURITY (3 jobs in parallel)

```
┌───────────────────────────────────────────────────────────────┐
│              SECURITY STAGE (Parallel)                        │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐ │
│  │security:snyk-    │  │security:snyk-    │  │security:   │ │
│  │dependencies      │  │code              │  │owasp-      │ │
│  ├──────────────────┤  ├──────────────────┤  │dependency- │ │
│  │ Scans:           │  │ Scans:           │  │check       │ │
│  │ • Maven deps     │  │ • Source code    │  ├────────────┤ │
│  │ • Transitive     │  │ • Security       │  │ Scans:     │ │
│  │   dependencies   │  │   issues         │  │ • Known    │ │
│  │ • Known CVEs     │  │ • Code patterns  │  │   CVEs     │ │
│  │                  │  │ • Best practices │  │ • CVSS     │ │
│  │ Threshold:       │  │                  │  │   scoring  │ │
│  │ • HIGH severity  │  │ Threshold:       │  │            │ │
│  │                  │  │ • HIGH severity  │  │ Threshold: │ │
│  │ Report:          │  │                  │  │ • CVSS >= 7│ │
│  │ • snyk-report.   │  │ Allow failure:   │  │            │ │
│  │   json           │  │ • true           │  │ Report:    │ │
│  │                  │  │                  │  │ • HTML     │ │
│  └──────────────────┘  └──────────────────┘  └────────────┘ │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**Security Coverage:**
- **Snyk**: Dependency vulnerabilities + Source code analysis
- **OWASP Dependency Check**: National Vulnerability Database (NVD)
- **Trivy**: Container image scanning (runs in package stage)

**Vulnerabilities Checked:**
- Spring Boot CVEs
- OAuth 2.0 / OIDC libraries
- PostgreSQL JDBC driver
- Redis client libraries
- JWT libraries
- Transitive dependencies

---

### Stage 6: PACKAGE (2 jobs)

```
┌─────────────────────────────────────────────────────────┐
│           PACKAGE STAGE (Sequential)                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────────────────────────────────────┐     │
│  │ package:docker-build                          │     │
│  ├───────────────────────────────────────────────┤     │
│  │ 1. Generate Dockerfile (if not exists)        │     │
│  │    • Base: eclipse-temurin:17-jre-alpine      │     │
│  │    • Non-root user (appuser:1000)             │     │
│  │    • Health check configured                  │     │
│  │                                               │     │
│  │ 2. Build Docker image                         │     │
│  │    • Multi-tag strategy:                      │     │
│  │      - ${IMAGE}:${CI_COMMIT_SHORT_SHA}        │     │
│  │      - ${IMAGE}:${SERVICE_ID}-${SHA}          │     │
│  │      - ${IMAGE}:${CI_COMMIT_REF_SLUG}         │     │
│  │      - ${IMAGE}:latest                        │     │
│  │                                               │     │
│  │ 3. Push to GitLab Container Registry          │     │
│  │    • All tags pushed                          │     │
│  │    • Image metadata added                     │     │
│  └───────────────────────────────────────────────┘     │
│                      │                                  │
│                      ▼                                  │
│  ┌───────────────────────────────────────────────┐     │
│  │ security:trivy-scan                           │     │
│  ├───────────────────────────────────────────────┤     │
│  │ Scans Docker image for:                       │     │
│  │ • OS vulnerabilities (Alpine Linux)           │     │
│  │ • JRE vulnerabilities                         │     │
│  │ • Application dependencies                    │     │
│  │ • Misconfigurations                           │     │
│  │                                               │     │
│  │ Severity: CRITICAL, HIGH                      │     │
│  │ Report: trivy-report.json                     │     │
│  └───────────────────────────────────────────────┘     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Docker Image Tags:**
```
registry.gitlab.com/org/project/user-management-service:
  - a1b2c3d (commit SHA)
  - SVC-001-a1b2c3d (service ID + SHA)
  - main (branch name)
  - latest
```

**Image Labels:**
```yaml
com.service.id: SVC-001
com.service.name: user-management-service
com.service.version: ${BUILD_VERSION}
com.service.commit: ${CI_COMMIT_SHA}
```

---

### Stage 7: DEPLOY (2 jobs)

```
┌──────────────────────────────────────────────────────────────┐
│              DEPLOY STAGE (Manual Trigger)                   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ deploy:pre-check                                   │     │
│  ├────────────────────────────────────────────────────┤     │
│  │ Validates dependency availability:                 │     │
│  │                                                    │     │
│  │ 1. PostgreSQL Connectivity                         │     │
│  │    kubectl run pg-check...                         │     │
│  │    ├─ Host: ${DB_HOST}                             │     │
│  │    ├─ Port: ${DB_PORT}                             │     │
│  │    └─ Test: SELECT 1                               │     │
│  │                                                    │     │
│  │ 2. Redis Connectivity                              │     │
│  │    kubectl run redis-check...                      │     │
│  │    ├─ Host: ${REDIS_HOST}                          │     │
│  │    ├─ Port: ${REDIS_PORT}                          │     │
│  │    └─ Test: PING                                   │     │
│  │                                                    │     │
│  │ 3. Event Bus Connectivity                          │     │
│  │    kubectl run eventbus-check...                   │     │
│  │    ├─ Host: ${EVENT_BUS_HOST}                      │     │
│  │    ├─ Port: ${EVENT_BUS_PORT}                      │     │
│  │    └─ Test: nc -zv (port check)                    │     │
│  └────────────────────────────────────────────────────┘     │
│                           │                                  │
│                           ▼                                  │
│  ┌────────────────────────────────────────────────────┐     │
│  │ deploy:development (Manual)                        │     │
│  ├────────────────────────────────────────────────────┤     │
│  │ 1. Create namespace (if not exists)                │     │
│  │    kubectl create namespace ${KUBE_NAMESPACE}      │     │
│  │                                                    │     │
│  │ 2. Create/Update Secrets                           │     │
│  │    • postgres-credentials                          │     │
│  │    • redis-credentials                             │     │
│  │    • event-bus-credentials                         │     │
│  │    • jwt-credentials                               │     │
│  │    • oauth2-credentials                            │     │
│  │                                                    │     │
│  │ 3. Create/Update ConfigMap                         │     │
│  │    • Database configuration                        │     │
│  │    • Redis configuration                           │     │
│  │    • Event Bus configuration                       │     │
│  │    • Service metadata                              │     │
│  │                                                    │     │
│  │ 4. Apply Kubernetes Manifests                      │     │
│  │    • Deployment (with health probes)               │     │
│  │    • Service (ClusterIP)                           │     │
│  │    • HPA (optional)                                │     │
│  │                                                    │     │
│  │ 5. Update deployment image                         │     │
│  │    kubectl set image deployment/...                │     │
│  │                                                    │     │
│  │ 6. Wait for rollout completion (5m timeout)        │     │
│  │    kubectl rollout status deployment/...           │     │
│  │                                                    │     │
│  │ 7. Verify deployment                               │     │
│  │    • List pods                                     │     │
│  │    • Check service endpoints                       │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Deployment Strategy:**
- **Type**: Rolling Update
- **Max Surge**: 1
- **Max Unavailable**: 0
- **Timeout**: 5 minutes

**Health Probes:**
- **Startup Probe**: /actuator/health (12 retries, 10s interval)
- **Liveness Probe**: /actuator/health/liveness (10s interval)
- **Readiness Probe**: /actuator/health/readiness (5s interval)

---

### Stage 8: SMOKE TEST (1 job)

```
┌──────────────────────────────────────────────────────────────┐
│              SMOKE TEST STAGE (Post-Deployment)              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │ smoke-test:api-health                              │     │
│  ├────────────────────────────────────────────────────┤     │
│  │ Base URL: ${DEPLOYMENT_URL}                        │     │
│  │                                                    │     │
│  │ Test 1: Health Check                               │     │
│  │   GET /actuator/health                             │     │
│  │   Expected: HTTP 200                               │     │
│  │                                                    │     │
│  │ Test 2: User Registration                          │     │
│  │   POST /api/auth/register                          │     │
│  │   Expected: HTTP 400/422 (validation error)        │     │
│  │                                                    │     │
│  │ Test 3: User Login                                 │     │
│  │   POST /api/auth/login                             │     │
│  │   Expected: HTTP 401 (invalid credentials)         │     │
│  │                                                    │     │
│  │ Test 4: Token Refresh                              │     │
│  │   POST /api/auth/refresh                           │     │
│  │   Expected: HTTP 401 (no token)                    │     │
│  │                                                    │     │
│  │ Test 5: List Users                                 │     │
│  │   GET /api/users                                   │     │
│  │   Expected: HTTP 401 (auth required)               │     │
│  │                                                    │     │
│  │ Test 6: Get User by ID                             │     │
│  │   GET /api/users/{id}                              │     │
│  │   Expected: HTTP 401/404                           │     │
│  │                                                    │     │
│  │ Test 7: User Preferences                           │     │
│  │   GET /api/users/preferences                       │     │
│  │   Expected: HTTP 401 (auth required)               │     │
│  │                                                    │     │
│  │ Test 8: Emergency Access                           │     │
│  │   GET /api/users/emergency-access                  │     │
│  │   Expected: HTTP 401 (auth required)               │     │
│  │                                                    │     │
│  │ Retry: 3 attempts                                  │     │
│  │ Fail Strategy: Exit pipeline on failure            │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Smoke Test Philosophy:**
- Verify endpoint **availability**, not full functionality
- Expect auth failures (401) as success (proves auth is working)
- Expect validation errors (400) as success (proves validation is working)
- Fast execution (< 2 minutes)
- Retry on transient failures

---

### Stage 9: NOTIFY (2 jobs)

```
┌──────────────────────────────────────────────────────────┐
│              NOTIFY STAGE (Conditional)                  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │ notify:success (on_success)                  │       │
│  ├──────────────────────────────────────────────┤       │
│  │ Triggers when: Pipeline succeeds              │       │
│  │                                              │       │
│  │ Notifications:                               │       │
│  │ • Slack webhook (formatted message)          │       │
│  │   - Service name & ID                        │       │
│  │   - Environment                              │       │
│  │   - Branch & commit SHA                      │       │
│  │   - Pipeline URL                             │       │
│  │   - Build author                             │       │
│  │                                              │       │
│  │ Message Format:                              │       │
│  │ ✅ Pipeline SUCCESS                          │       │
│  │ Service: user-management-service (SVC-001)   │       │
│  │ Branch: main                                 │       │
│  │ Commit: a1b2c3d                              │       │
│  │ Pipeline: <link>                             │       │
│  └──────────────────────────────────────────────┘       │
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │ notify:failure (on_failure)                  │       │
│  ├──────────────────────────────────────────────┤       │
│  │ Triggers when: Any job fails                 │       │
│  │                                              │       │
│  │ Notifications:                               │       │
│  │ • Slack webhook (error message)              │       │
│  │   - Service name & ID                        │       │
│  │   - Failed job name                          │       │
│  │   - Branch & commit SHA                      │       │
│  │   - Pipeline URL                             │       │
│  │   - Failure timestamp                        │       │
│  │                                              │       │
│  │ • Email (optional)                           │       │
│  │   To: ${NOTIFICATION_EMAIL}                  │       │
│  │   Subject: CI/CD Failure: SVC-001            │       │
│  │                                              │       │
│  │ Message Format:                              │       │
│  │ ❌ Pipeline FAILED                           │       │
│  │ Service: user-management-service (SVC-001)   │       │
│  │ Failed Job: test:integration                 │       │
│  │ Branch: develop                              │       │
│  │ Commit: x7y8z9                               │       │
│  │ Pipeline: <link>                             │       │
│  │ ⚠️ Action Required: Review logs              │       │
│  └──────────────────────────────────────────────┘       │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## Dependency Graph

```
┌────────────────────────────────────────────────────────────────┐
│                    EXTERNAL DEPENDENCIES                       │
└────────────────────────────────────────────────────────────────┘

┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│  PostgreSQL   │         │     Redis     │         │  Event Bus    │
│   Database    │         │     Cache     │         │  (RabbitMQ)   │
├───────────────┤         ├───────────────┤         ├───────────────┤
│ Host: DB_HOST │         │ Host: REDIS_  │         │ Host: EVENT_  │
│ Port: 5432    │         │       HOST    │         │       BUS_HOST│
│ DB: userserv  │         │ Port: 6379    │         │ Port: 5672    │
│     ice_db    │         │ Auth: Redis   │         │ Auth: Required│
│ Auth: Required│         │       pwd     │         │               │
└───────────────┘         └───────────────┘         └───────────────┘
        │                         │                         │
        └─────────────────────────┼─────────────────────────┘
                                  │
                                  ▼
                    ┌───────────────────────────┐
                    │   User Management Service │
                    │        (SVC-001)          │
                    └───────────────────────────┘
                                  │
                ┌─────────────────┼─────────────────┐
                │                 │                 │
                ▼                 ▼                 ▼
        ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
        │   SonarCloud │  │     Snyk     │  │GitLab Registry
        │   Analysis   │  │   Security   │  │ Container Reg│
        └──────────────┘  └──────────────┘  └──────────────┘
```

---

## Pipeline Execution Matrix

| Stage | Jobs | Parallel | Duration | Artifacts | Can Fail |
|-------|------|----------|----------|-----------|----------|
| validate | 2 | Yes | ~1 min | build.env | Yes (health) |
| build | 2 | No | ~2-3 min | JAR, classes | No |
| test | 2 | Yes | ~5-7 min | JUnit, Coverage | No |
| analyze | 1 | No | ~2-3 min | None | Yes |
| security | 3 | Yes | ~3-5 min | Reports | Yes |
| package | 2 | No | ~3-4 min | Docker image | No |
| deploy | 2 | No | ~2-3 min | None | No |
| smoke-test | 1 | No | ~1-2 min | None | No |
| notify | 1-2 | No | ~10 sec | None | Yes |

**Total Pipeline Duration:** ~20-30 minutes (with all stages)

---

## Resource Requirements

### GitLab Runner Requirements

```yaml
Executor: docker
Resources:
  CPU: 2-4 cores
  Memory: 4-8 GB RAM
  Disk: 20 GB SSD

Docker Socket: Required
Privileged Mode: Required (for Docker-in-Docker)
```

### Kubernetes Cluster Requirements

```yaml
Node Pool:
  Minimum Nodes: 2
  CPU per Node: 2 cores
  Memory per Node: 4 GB

Service Requirements:
  - PostgreSQL: 512Mi RAM, 0.5 CPU
  - Redis: 256Mi RAM, 0.25 CPU
  - Event Bus: 512Mi RAM, 0.5 CPU
  - Application: 512Mi-1Gi RAM, 0.25-1 CPU
```

---

## Environment Variables Flow

```
┌────────────────────────────────────────────────────┐
│         GitLab CI/CD Variables (Settings)          │
└────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   Build Env  │ │  K8s Secrets │ │ K8s ConfigMap│
├──────────────┤ ├──────────────┤ ├──────────────┤
│ • Service ID │ │ • DB creds   │ │ • DB host    │
│ • Build ver  │ │ • Redis pwd  │ │ • Redis host │
│ • Commit SHA │ │ • JWT secret │ │ • EventBus   │
│ • Timestamp  │ │ • OAuth cred │ │ • Service ID │
└──────────────┘ └──────────────┘ └──────────────┘
        │               │               │
        └───────────────┼───────────────┘
                        │
                        ▼
        ┌────────────────────────────────┐
        │    Application Container       │
        │    (Environment Variables)     │
        └────────────────────────────────┘
```

---

## Security Layers

```
┌─────────────────────────────────────────────────────────┐
│                   SECURITY LAYERS                       │
└─────────────────────────────────────────────────────────┘

Layer 1: Source Code Security
├─ SonarCloud (Code Quality & Security)
└─ Snyk Code (Static Analysis)

Layer 2: Dependency Security
├─ Snyk (Open Source Dependencies)
├─ OWASP Dependency Check (CVE Database)
└─ Maven Dependency Analysis

Layer 3: Container Security
├─ Trivy (Image Scanning)
├─ Non-root user (UID 1000)
└─ Minimal base image (Alpine)

Layer 4: Runtime Security
├─ Kubernetes Network Policies
├─ Pod Security Standards
├─ RBAC (Role-Based Access Control)
└─ Secret Management (Kubernetes Secrets)

Layer 5: Access Control
├─ Protected GitLab Variables
├─ Masked Sensitive Values
├─ GCP Service Account (Least Privilege)
└─ Registry Authentication
```

---

## Rollback Strategy

```
┌────────────────────────────────────────────────────┐
│              ROLLBACK PROCEDURE                    │
└────────────────────────────────────────────────────┘

Automatic Rollback Triggers:
• Deployment fails to reach ready state (5m timeout)
• Health check failures exceed threshold
• Smoke tests fail (pipeline blocks)

Manual Rollback Commands:
┌──────────────────────────────────────────────────┐
│ # Rollback to previous version                   │
│ kubectl rollout undo deployment/user-management- │
│   service -n user-management                     │
│                                                  │
│ # Rollback to specific revision                 │
│ kubectl rollout undo deployment/user-management- │
│   service -n user-management --to-revision=2     │
│                                                  │
│ # Check rollout history                         │
│ kubectl rollout history deployment/user-         │
│   management-service -n user-management          │
└──────────────────────────────────────────────────┘

Rolling Update Strategy:
• MaxSurge: 1 (allows 1 extra pod during update)
• MaxUnavailable: 0 (ensures zero downtime)
• Gradual rollout with automatic rollback on failure
```

---

## Monitoring & Observability

```
┌────────────────────────────────────────────────────┐
│           MONITORING INTEGRATION                   │
└────────────────────────────────────────────────────┘

Application Metrics:
├─ Endpoint: /actuator/prometheus
├─ Scrape: Prometheus (via annotation)
└─ Metrics: JVM, HTTP, Database, Custom

Pipeline Monitoring:
├─ GitLab Pipeline Analytics
├─ Job duration tracking
├─ Success/failure rates
└─ Artifact storage usage

Deployment Tracking:
├─ GitLab Environments
├─ Deployment frequency
├─ Lead time for changes
└─ Change failure rate

Alerts:
├─ Slack notifications (success/failure)
├─ Email notifications (failures)
├─ Pipeline failure trends
└─ Security scan alerts
```

---

## Best Practices Implemented

✅ **Zero-downtime deployments** (RollingUpdate with MaxUnavailable: 0)
✅ **Comprehensive testing** (Unit, Integration, Smoke tests)
✅ **Security scanning** (Snyk, OWASP, Trivy, SonarCloud)
✅ **Dependency validation** (Pre-deployment checks)
✅ **Efficient caching** (Maven repository caching)
✅ **Multi-stage Docker builds** (Optimized layers)
✅ **Health probes** (Startup, Liveness, Readiness)
✅ **Secret management** (Kubernetes Secrets, masked variables)
✅ **Artifact archiving** (JUnit reports, coverage, security reports)
✅ **Notifications** (Slack, Email on failures)
✅ **Manual deployment gates** (Manual approval for production)
✅ **Rollback capability** (Kubernetes rollout undo)
✅ **Environment segregation** (Dev, Staging, Production)
✅ **Service identification** (Service ID tagging)
✅ **Observability** (Prometheus metrics, health endpoints)

---

**Document Version:** 1.0.0
**Last Updated:** 2026-01-12
**Maintained By:** DevOps Engineering Team
