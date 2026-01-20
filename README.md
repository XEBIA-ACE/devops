# Go Application CI/CD Pipeline

Production-grade GitLab CI/CD pipeline for Go applications with integrated security scanning, quality gates, and automated deployments to AWS ECS.

## Features

- **Optimized Build Pipeline:** Aggressive caching strategy for Go dependencies (70% faster builds)
- **Quality Gates:** Unit tests with coverage thresholds + golangci-lint static analysis
- **Security Scanning:** OWASP Dependency-Check + Trivy container scanning
- **AWS ECR Integration:** Automated Docker image builds with commit SHA tagging
- **Multi-Environment Deployment:** Linear deployment flow to QA and UAT environments
- **Failure Notifications:** Slack alerts for pipeline failures
- **Environment Tracking:** Native GitLab environments for deployment history

## Pipeline Stages

```
build → test → security → package → deploy-qa → deploy-uat → notify
```

1. **Build:** Compile Go application with dependency caching
2. **Test:** Run unit tests (60% coverage minimum) + golangci-lint static analysis
3. **Security:** OWASP dependency scanning (fail on CVSS ≥7)
4. **Package:** Build Docker image, scan with Trivy, push to AWS ECR
5. **Deploy QA:** Auto-deploy to QA environment on `develop`/`main` branches
6. **Deploy UAT:** Manual deployment to UAT on `main` branch
7. **Notify:** Slack notification on pipeline failure

## Quick Start

### 1. Prerequisites

- GitLab account with CI/CD enabled
- AWS account with:
  - ECR repository created
  - ECS clusters and services configured (QA + UAT)
  - IAM credentials with ECR/ECS permissions
- Slack workspace with incoming webhook

### 2. Setup

Follow the detailed setup instructions in **[SETUP_GUIDE.md](SETUP_GUIDE.md)**

**Quick checklist:**
- [ ] Add `.gitlab-ci.yml` to your repository
- [ ] Configure 10 required CI/CD variables in GitLab
- [ ] Create AWS ECR repository
- [ ] Set up ECS clusters and services
- [ ] Configure Slack webhook
- [ ] Add `Dockerfile` to project root
- [ ] Push to repository and verify pipeline runs

### 3. Required GitLab Variables

Configure these in **Settings → CI/CD → Variables:**

**AWS Configuration:**
- `AWS_ACCESS_KEY_ID` (masked, protected)
- `AWS_SECRET_ACCESS_KEY` (masked, protected)
- `AWS_REGION`
- `AWS_ECR_REGISTRY`
- `AWS_ECR_REPOSITORY`

**ECS Configuration:**
- `ECS_CLUSTER_QA`
- `ECS_SERVICE_QA`
- `ECS_CLUSTER_UAT`
- `ECS_SERVICE_UAT`

**Notifications:**
- `SLACK_WEBHOOK_URL` (masked, protected)

See **[SETUP_GUIDE.md](SETUP_GUIDE.md)** for detailed configuration instructions.

## Usage

### Automatic Deployments

**Develop branch:**
```bash
git checkout develop
git add .
git commit -m "feat: new feature"
git push origin develop
```
Result: Auto-deploys to QA after all checks pass

**Main branch:**
```bash
git checkout main
git merge develop
git push origin main
```
Result: Auto-deploys to QA, UAT requires manual approval

### Manual UAT Deployment

1. Go to **CI/CD → Pipelines**
2. Select the pipeline for `main` branch
3. Click **Play** (▶️) button next to `deploy:uat` job

### Viewing Pipeline Results

**Pipeline Status:**
```
GitLab → CI/CD → Pipelines → Click pipeline #
```

**Artifacts:**
- `coverage.out` - Test coverage report (1 week retention)
- `dependency-check-report/` - OWASP security scan results (1 week retention)

**Environment History:**
```
GitLab → Deployments → Environments → [QA|UAT]
```

## Pipeline Configuration

### Customization Options

**Adjust Coverage Threshold** (.gitlab-ci.yml:72-75):
```yaml
if (( $(echo "$COVERAGE < 60" | bc -l) )); then  # Change 60 to desired %
```

**Modify OWASP Severity** (.gitlab-ci.yml:113):
```yaml
--failOnCVSS 7  # Change to 5 (medium) or 9 (critical only)
```

**Change Go Version** (.gitlab-ci.yml:10):
```yaml
GO_VERSION: "1.21"  # Update to latest stable version
```

**Add Deployment Environments:**
```yaml
deploy:prod:
  stage: deploy-prod
  environment:
    name: production
    url: https://prod.example.com
  only:
    - tags  # Deploy only on tagged releases
  when: manual
```

### Cache Management

Cache is automatically managed with key `${CI_COMMIT_REF_SLUG}-go`. To clear cache:

```
GitLab → CI/CD → Pipelines → Clear runner caches
```

## Project Structure

Required structure for pipeline to work:

```
project-root/
├── .gitlab-ci.yml          # Pipeline configuration
├── Dockerfile              # Container image definition
├── go.mod                  # Go module file
├── go.sum                  # Dependency checksums
├── cmd/
│   └── app/
│       └── main.go         # Application entry point (must be here)
├── internal/               # Private application code
├── pkg/                    # Public libraries
└── ...
```

## Environment URLs

Update environment URLs in `.gitlab-ci.yml`:

```yaml
environment:
  name: qa
  url: https://qa.${CI_PROJECT_NAME}.example.com  # Change to actual URL
```

## Security

### Built-in Security Measures

1. **OWASP Dependency-Check:** Scans for known vulnerabilities in dependencies
2. **Trivy Image Scanning:** Detects vulnerabilities in container images
3. **Distroless Base Image:** Minimal attack surface (no shell, no package manager)
4. **Non-root User:** Container runs as `nonroot` user (UID 65532)
5. **Static Binary:** No runtime dependencies (CGO disabled)

### Handling Security Failures

**Dependency vulnerabilities:**
1. Review `dependency-check-report/` artifact
2. Update vulnerable dependencies in `go.mod`
3. If false positive, add suppression file

**Container vulnerabilities:**
1. Review Trivy scan output in job logs
2. Update base image or application dependencies
3. Consider using `--severity CRITICAL` for less strict scanning

## Monitoring and Debugging

### View Job Logs

```
GitLab → CI/CD → Pipelines → Click pipeline → Click job
```

### Debug Failed Jobs

Enable debug traces for specific jobs:

```yaml
job_name:
  variables:
    CI_DEBUG_TRACE: "true"
```

### Common Issues

See **[SETUP_GUIDE.md](SETUP_GUIDE.md#troubleshooting)** for detailed troubleshooting.

**Quick fixes:**
- **AWS authentication fails:** Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- **Cache not working:** Check runner executor supports caching
- **Tests failing:** Run locally first: `go test ./...`
- **Linting errors:** Run locally: `golangci-lint run`

## Performance

### Build Times

Typical pipeline duration:

| Stage | First Run | Cached Run |
|-------|-----------|------------|
| Build | ~2min | ~30s |
| Test | ~1min | ~45s |
| Security | ~3min | ~3min |
| Package | ~4min | ~2min |
| Deploy | ~2min | ~2min |
| **Total** | **~12min** | **~8min** |

### Optimization Tips

1. **Cache warm-up:** First pipeline run on a branch is slower
2. **Parallel jobs:** Test and lint run in parallel
3. **Dependency updates:** Only rebuild when `go.mod` changes
4. **Image layers:** Dockerfile optimized for layer caching

## Notifications

### Slack Alerts

Failure notifications include:
- Project name and branch
- Commit SHA and author
- Direct link to failed pipeline

**Customize notification format** (.gitlab-ci.yml:253-289):
```yaml
# Modify JSON payload to change message format
```

**Add success notifications:**
```yaml
notify:success:
  stage: notify
  script:
    - curl -X POST ${SLACK_WEBHOOK_URL} ...
  when: on_success
  only:
    - main
```

## CI/CD Best Practices

1. **Small commits:** Faster pipeline execution and easier debugging
2. **Feature branches:** Test changes before merging to `develop`
3. **Protected branches:** Enable branch protection on `main` and `develop`
4. **Semantic versioning:** Tag releases: `git tag v1.0.0`
5. **Review artifacts:** Check security and coverage reports regularly

## Migration from Other CI Systems

### From Jenkins

- Replace `Jenkinsfile` with `.gitlab-ci.yml`
- Convert `credentials()` to GitLab variables
- Use GitLab runners instead of Jenkins agents

### From GitHub Actions

- Rename workflows to stages
- Convert `secrets.GITHUB_TOKEN` to `$CI_JOB_TOKEN`
- Use GitLab cache instead of `actions/cache`

### From CircleCI

- Convert `.circleci/config.yml` to `.gitlab-ci.yml`
- Replace `orbs` with GitLab templates (if needed)
- Use GitLab artifacts instead of CircleCI workspaces

## Contributing

To improve this pipeline:

1. Create feature branch: `git checkout -b improve-pipeline`
2. Modify `.gitlab-ci.yml`
3. Test changes in pipeline
4. Create merge request with description of changes

## License

This pipeline configuration is provided as-is for production use.

## Support

- **Setup Issues:** See [SETUP_GUIDE.md](SETUP_GUIDE.md)
- **GitLab CI Docs:** https://docs.gitlab.com/ee/ci/
- **Go Best Practices:** https://go.dev/doc/effective_go

---

**Pipeline Status:**

[![Pipeline Status](https://gitlab.com/your-namespace/your-project/badges/main/pipeline.svg)](https://gitlab.com/your-namespace/your-project/-/pipelines)
[![Coverage](https://gitlab.com/your-namespace/your-project/badges/main/coverage.svg)](https://gitlab.com/your-namespace/your-project/-/pipelines)
