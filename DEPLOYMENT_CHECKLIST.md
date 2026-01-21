# Production Deployment Checklist

Use this checklist to ensure a safe and successful deployment of the data processing application.

## Pre-Deployment Checklist

### 1. Environment Preparation

- [ ] Kubernetes cluster is accessible and healthy
- [ ] kubectl is configured with correct context
- [ ] Required Kubernetes version: v1.24+
- [ ] CNI supports Network Policies (Calico, Cilium, etc.)
- [ ] Metrics Server is installed and running
- [ ] Cluster has sufficient resources (CPU, Memory, Storage)

### 2. Dependencies Installation

- [ ] External Secrets Operator installed (if using)
- [ ] Cert-manager installed (if using Let's Encrypt)
- [ ] Prometheus Adapter installed (if using custom metrics for HPA)
- [ ] Prometheus installed (for metrics collection)
- [ ] Monitoring namespace exists and is labeled

### 3. Configuration Updates

- [ ] Updated container image references in `deployment.yaml`
  - Current: `your-registry.example.com/data-processing:1.0.0`
  - Updated to: `_______________`

- [ ] Updated domain names in `ingress.yaml`
  - Current: `data-processing.example.com`
  - Updated to: `_______________`

- [ ] Updated TLS certificate configuration
  - Using cert-manager: [ ] Yes [ ] No
  - Using External Secrets: [ ] Yes [ ] No
  - Using manual secrets: [ ] Yes [ ] No

- [ ] Updated HAProxy LoadBalancer annotations in `service.yaml`
  - Cloud provider: [ ] AWS [ ] GCP [ ] Azure [ ] Other
  - LoadBalancer type configured: `_______________`

- [ ] Updated resource requests/limits in `deployment.yaml`
  - Based on actual workload requirements
  - Tested in staging environment

- [ ] Updated application configuration in `configmap.yaml`
  - Database connection strings
  - External API endpoints
  - Feature flags
  - Worker threads and batch sizes

- [ ] Updated External Secrets configuration in `secrets.yaml`
  - Vault/AWS Secrets Manager endpoint
  - Secret paths and keys
  - Authentication method

### 4. Secrets Management

- [ ] TLS certificates are available
  - Cert path: `_______________`
  - Key path: `_______________`

- [ ] Application secrets are stored in secret manager
  - Database password: [ ] Created
  - API key: [ ] Created
  - Encryption key: [ ] Created

- [ ] External Secrets Operator SecretStore configured
  - Backend type: `_______________`
  - Authentication method: `_______________`

- [ ] HAProxy stats authentication configured
  - Username: `_______________`
  - Password: [ ] Set

### 5. Network Configuration

- [ ] Dependent namespaces exist and are labeled
  - kube-system: [ ] Exists [ ] Labeled
  - monitoring: [ ] Exists [ ] Labeled
  - database: [ ] Exists [ ] Labeled
  - cache: [ ] Exists [ ] Labeled
  - kafka: [ ] Exists [ ] Labeled

- [ ] DNS configuration verified
  - External DNS configured: [ ] Yes [ ] No
  - Domain points to LoadBalancer: [ ] Yes [ ] No

- [ ] Network policies reviewed and approved
  - Ingress rules: [ ] Reviewed
  - Egress rules: [ ] Reviewed
  - Dependent services accessible: [ ] Verified

### 6. Storage Configuration

- [ ] HostPath directories exist on nodes (if using HostPath)
  - HAProxy data path: `/var/lib/haproxy-ingress`
  - Application data path: `/mnt/data-processing`
  - Permissions configured: [ ] Yes

- [ ] Backup strategy defined for HostPath volumes
  - Backup tool: `_______________`
  - Backup schedule: `_______________`

### 7. Security Review

- [ ] RBAC policies reviewed and approved
  - Least privilege principle followed
  - Service account permissions documented

- [ ] Network policies reviewed by security team
  - Default deny-all policies in place
  - Explicit allow rules documented

- [ ] Pod Security Standards enforced
  - Non-root users configured
  - Read-only root filesystem enabled
  - Capabilities dropped

- [ ] Secrets rotation policy defined
  - Rotation schedule: `_______________`
  - Automation in place: [ ] Yes [ ] No

- [ ] Image scanning completed
  - No critical vulnerabilities: [ ] Yes [ ] No
  - Scan tool: `_______________`
  - Scan date: `_______________`

### 8. Monitoring and Observability

- [ ] Prometheus scrape configs updated
  - HAProxy metrics endpoint configured
  - Application metrics endpoint configured

- [ ] Grafana dashboards created
  - HAProxy dashboard: [ ] Created
  - Application dashboard: [ ] Created

- [ ] Alerting rules configured
  - Pod crash alerts: [ ] Created
  - High CPU/Memory alerts: [ ] Created
  - Error rate alerts: [ ] Created

- [ ] Logging pipeline configured
  - Log aggregation tool: `_______________`
  - Log retention period: `_______________`

### 9. Testing

- [ ] Dry-run deployment successful
  ```bash
  ./deploy.sh --dry-run
  ```

- [ ] Manifests validated
  ```bash
  kubectl apply --dry-run=client -f .
  ```

- [ ] Kustomize build successful (if using)
  ```bash
  kustomize build . > /dev/null
  ```

### 10. Documentation

- [ ] Runbook updated
- [ ] Architecture diagram updated
- [ ] On-call contacts updated
- [ ] Incident response procedures documented
- [ ] Rollback procedures documented

## Deployment Process

### Phase 1: Initial Deployment (Non-Production)

1. [ ] Deploy to development environment
   ```bash
   kubectl config use-context dev-cluster
   ./deploy.sh
   ```

2. [ ] Verify development deployment
   ```bash
   ./deploy.sh --verify-only
   ```

3. [ ] Run smoke tests in development
   ```bash
   ./deploy.sh --smoke-test
   ```

4. [ ] Deploy to staging environment
   ```bash
   kubectl config use-context staging-cluster
   ./deploy.sh
   ```

5. [ ] Run full test suite in staging
   - [ ] Functional tests passed
   - [ ] Integration tests passed
   - [ ] Performance tests passed
   - [ ] Security tests passed

6. [ ] Staging deployment soaked for: `_____` hours/days

### Phase 2: Production Deployment

1. [ ] Change freeze confirmed (if applicable)

2. [ ] Backup current production state
   ```bash
   kubectl get all,cm,secret,ingress,hpa,pdb -n data-processing -o yaml > backup-$(date +%Y%m%d-%H%M%S).yaml
   ```

3. [ ] Switch to production context
   ```bash
   kubectl config use-context prod-cluster
   kubectl config current-context
   ```

4. [ ] Create secrets (if not using External Secrets)
   ```bash
   kubectl create secret tls haproxy-tls-secret --cert=... --key=... -n data-processing
   kubectl create secret generic data-processing-secrets ... -n data-processing
   ```

5. [ ] Label dependent namespaces
   ```bash
   kubectl label namespace kube-system name=kube-system --overwrite
   kubectl label namespace monitoring name=monitoring --overwrite
   ```

6. [ ] Deploy core resources
   ```bash
   kubectl apply -f namespace.yaml
   kubectl apply -f rbac.yaml
   kubectl apply -f configmap.yaml
   kubectl apply -f secrets.yaml
   ```

7. [ ] Wait for secrets to sync (if using External Secrets)
   ```bash
   kubectl wait --for=condition=Ready externalsecret/haproxy-tls-cert -n data-processing --timeout=60s
   kubectl wait --for=condition=Ready externalsecret/data-processing-credentials -n data-processing --timeout=60s
   ```

8. [ ] Deploy applications
   ```bash
   kubectl apply -f deployment.yaml
   kubectl apply -f service.yaml
   ```

9. [ ] Monitor rollout
   ```bash
   kubectl rollout status deployment/haproxy-ingress-controller -n data-processing
   kubectl rollout status deployment/data-processing-app -n data-processing
   ```

10. [ ] Deploy ingress
    ```bash
    kubectl apply -f ingress.yaml
    ```

11. [ ] Deploy autoscaling and availability
    ```bash
    kubectl apply -f hpa.yaml
    kubectl apply -f pdb.yaml
    ```

12. [ ] Deploy network policies
    ```bash
    kubectl apply -f network-policy.yaml
    ```

## Post-Deployment Verification

### 1. Resource Status

- [ ] All pods are running
  ```bash
  kubectl get pods -n data-processing
  ```

- [ ] All deployments are ready
  ```bash
  kubectl get deployments -n data-processing
  ```

- [ ] Services have endpoints
  ```bash
  kubectl get endpoints -n data-processing
  ```

- [ ] Ingress has address
  ```bash
  kubectl get ingress -n data-processing
  ```

- [ ] HPA is active
  ```bash
  kubectl get hpa -n data-processing
  ```

### 2. Connectivity Tests

- [ ] Internal service connectivity
  ```bash
  kubectl run test --rm -i --restart=Never --image=curlimages/curl -n data-processing -- \
    curl http://data-processing-app:8080/health
  ```

- [ ] External HTTPS connectivity
  ```bash
  curl -k https://data-processing.example.com/health
  ```

- [ ] TLS certificate valid
  ```bash
  curl -vI https://data-processing.example.com 2>&1 | grep "SSL certificate verify ok"
  ```

### 3. Network Policies

- [ ] Network policies are applied
  ```bash
  kubectl get networkpolicies -n data-processing
  ```

- [ ] Allowed traffic works (HAProxy to app)
  ```bash
  # Test from HAProxy pod
  kubectl exec -it -n data-processing <haproxy-pod> -- \
    wget -O- http://data-processing-app:8080/health
  ```

- [ ] Blocked traffic fails (from other namespaces)
  ```bash
  # Should fail
  kubectl run test --rm -i --restart=Never --image=curlimages/curl -n default -- \
    curl --max-time 5 http://data-processing-app.data-processing:8080/health
  ```

### 4. Autoscaling

- [ ] HPA is working
  ```bash
  kubectl get hpa -n data-processing
  kubectl describe hpa data-processing-app-hpa -n data-processing
  ```

- [ ] Metrics are available
  ```bash
  kubectl top pods -n data-processing
  ```

### 5. Monitoring

- [ ] Prometheus is scraping metrics
  - HAProxy metrics: http://localhost:9101/metrics
  - App metrics: http://localhost:9090/metrics

- [ ] Logs are flowing
  ```bash
  kubectl logs -n data-processing -l app=haproxy-ingress --tail=20
  kubectl logs -n data-processing -l app=data-processing --tail=20
  ```

- [ ] Dashboards are displaying data
  - Grafana HAProxy dashboard: [ ] Working
  - Grafana application dashboard: [ ] Working

- [ ] Alerts are configured
  - Alert manager receiving alerts: [ ] Yes
  - Test alert fired successfully: [ ] Yes

### 6. Load Testing (Optional)

- [ ] Load test executed
  - Tool used: `_______________`
  - Duration: `_______________`
  - RPS achieved: `_______________`

- [ ] HPA scaled up during load
  - Initial replicas: `_______________`
  - Max replicas reached: `_______________`

- [ ] HPA scaled down after load
  - Final replicas: `_______________`

### 7. Smoke Tests

- [ ] Health checks passing
  ```bash
  curl https://data-processing.example.com/health
  ```

- [ ] Application functionality verified
  - [ ] Data processing pipeline working
  - [ ] API endpoints responding
  - [ ] Database connections working

- [ ] Performance acceptable
  - Response time: `_____` ms
  - Error rate: `_____` %

## Rollback Procedure

If issues are detected:

1. [ ] Identify the issue
   - Check logs: `kubectl logs -n data-processing -l app=data-processing --tail=100`
   - Check events: `kubectl get events -n data-processing --sort-by='.lastTimestamp'`

2. [ ] Decide on rollback vs. fix-forward

3. [ ] If rollback needed:
   ```bash
   # Rollback deployments
   kubectl rollout undo deployment/haproxy-ingress-controller -n data-processing
   kubectl rollout undo deployment/data-processing-app -n data-processing

   # Or restore from backup
   kubectl apply -f backup-<timestamp>.yaml
   ```

4. [ ] Verify rollback successful

5. [ ] Update incident documentation

## Sign-off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Platform Engineer | ___________ | ___________ | ___________ |
| Security Engineer | ___________ | ___________ | ___________ |
| DevOps Lead | ___________ | ___________ | ___________ |
| Engineering Manager | ___________ | ___________ | ___________ |

## Notes

```
Additional deployment notes, issues encountered, or deviations from standard procedure:

_______________________________________________________________________________

_______________________________________________________________________________

_______________________________________________________________________________

```

## Post-Deployment Follow-up

- [ ] Monitor deployment for 24 hours
- [ ] Check error rates and latency
- [ ] Review resource utilization
- [ ] Update capacity planning docs
- [ ] Schedule post-deployment review meeting
  - Date: `_______________`
  - Attendees: `_______________`

## Success Criteria

Deployment is considered successful when:

- [ ] All pods are running and healthy for 1 hour
- [ ] No error rate increase observed
- [ ] Response times within acceptable range (< `____` ms p99)
- [ ] HPA scaling working as expected
- [ ] Monitoring and alerting functional
- [ ] No security policy violations
- [ ] Rollback plan tested and documented
