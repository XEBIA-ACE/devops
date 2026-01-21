# Data Processing Kubernetes Deployment

Production-ready Kubernetes manifests for a data processing application with HAProxy Ingress controller, comprehensive security controls, and autoscaling capabilities.

## Architecture Overview

This deployment includes:

- **HAProxy Ingress Controller**: High-performance load balancer with TLS termination
- **Data Processing Application**: Scalable worker pods for data processing tasks
- **Storage**: HostPath volumes for persistent data
- **Security**: RBAC, Network Policies, Pod Security Standards
- **High Availability**: Pod Disruption Budgets, topology spread constraints
- **Autoscaling**: Horizontal Pod Autoscaler with CPU/memory and custom metrics
- **Observability**: Prometheus metrics, structured logging

## Directory Structure

```
.
├── namespace.yaml           # Namespace with resource quotas and limits
├── rbac.yaml               # ServiceAccounts, Roles, RoleBindings
├── configmap.yaml          # Application and HAProxy configuration
├── secrets.yaml            # External Secrets integration
├── deployment.yaml         # HAProxy and application deployments
├── service.yaml            # Service definitions (LoadBalancer, ClusterIP)
├── ingress.yaml            # Ingress resources with TLS
├── hpa.yaml               # Horizontal Pod Autoscaler
├── pdb.yaml               # Pod Disruption Budgets
├── network-policy.yaml    # Network policies for traffic control
├── kustomization.yaml     # Kustomize configuration
└── README.md              # This file
```

## Prerequisites

1. **Kubernetes Cluster**: v1.24+ with CNI supporting Network Policies
2. **kubectl**: v1.24+
3. **kustomize**: v4.5+ (or kubectl with built-in kustomize)
4. **External Secrets Operator**: For secret management (optional)
5. **Cert-manager**: For TLS certificate management (optional)
6. **Prometheus Adapter**: For custom metrics (optional)
7. **Metrics Server**: For HPA CPU/memory metrics

## Pre-Deployment Configuration

### 1. Update Configuration Values

Edit the following files to match your environment:

**configmap.yaml**:
- Update application-specific configuration values
- Modify HAProxy settings for your use case

**secrets.yaml**:
- Configure External Secrets Operator SecretStore
- Update Vault/AWS Secrets Manager connection details
- Or create manual secrets for testing

**ingress.yaml**:
- Replace `data-processing.example.com` with your domain
- Update TLS certificate configuration
- Configure cert-manager ClusterIssuer if using Let's Encrypt

**deployment.yaml**:
- Replace `your-registry.example.com/data-processing:1.0.0` with your actual container image
- Adjust resource requests/limits based on your workload
- Update node selectors and tolerations if using specific node pools

**service.yaml**:
- Update LoadBalancer annotations for your cloud provider (AWS/GCP/Azure)
- Configure external DNS hostname

### 2. Create Required Secrets (Manual Method)

If not using External Secrets Operator:

```bash
# Create TLS certificate secret
kubectl create secret tls haproxy-tls-secret \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n data-processing

# Create application secrets
kubectl create secret generic data-processing-secrets \
  --from-literal=database-password=your-password \
  --from-literal=api-key=your-api-key \
  --from-literal=encryption-key=your-encryption-key \
  -n data-processing

# Create HAProxy stats authentication
htpasswd -c auth admin
kubectl create secret generic haproxy-stats-auth \
  --from-file=auth=auth \
  -n data-processing
```

### 3. Label Existing Namespaces

For Network Policies to work correctly, label dependent namespaces:

```bash
kubectl label namespace kube-system name=kube-system
kubectl label namespace monitoring name=monitoring
kubectl label namespace database name=database
kubectl label namespace cache name=cache
kubectl label namespace kafka name=kafka
```

## Deployment

### Option 1: Deploy with kubectl

Deploy all resources in order:

```bash
# Deploy core resources
kubectl apply -f namespace.yaml
kubectl apply -f rbac.yaml
kubectl apply -f configmap.yaml

# Deploy secrets (if using External Secrets Operator)
kubectl apply -f secrets.yaml

# Wait for secrets to be created
kubectl wait --for=condition=Ready externalsecret/haproxy-tls-cert -n data-processing --timeout=60s

# Deploy applications
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml

# Deploy autoscaling and availability
kubectl apply -f hpa.yaml
kubectl apply -f pdb.yaml

# Deploy network policies (last, to avoid blocking deployment)
kubectl apply -f network-policy.yaml
```

### Option 2: Deploy with Kustomize

```bash
# Deploy all resources at once
kubectl apply -k .

# Or using kustomize separately
kustomize build . | kubectl apply -f -
```

### Option 3: Deploy with Helm (Convert to Helm Chart)

```bash
# Convert Kustomize to Helm
kustomize build . | helm template data-processing - | kubectl apply -f -
```

## Verification

### Check Deployment Status

```bash
# Check all resources
kubectl get all -n data-processing

# Check pods
kubectl get pods -n data-processing -o wide

# Check services
kubectl get svc -n data-processing

# Check ingress
kubectl get ingress -n data-processing

# Check HPA status
kubectl get hpa -n data-processing

# Check PDB status
kubectl get pdb -n data-processing

# Check network policies
kubectl get networkpolicies -n data-processing
```

### View Logs

```bash
# HAProxy Ingress Controller logs
kubectl logs -n data-processing -l app=haproxy-ingress --tail=100 -f

# Application logs
kubectl logs -n data-processing -l app=data-processing --tail=100 -f

# View logs from specific container
kubectl logs -n data-processing <pod-name> -c data-processor
```

### Test Connectivity

```bash
# Test external access
curl -k https://data-processing.example.com/health

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://data-processing-app.data-processing.svc.cluster.local:8080/health

# Test network policies
kubectl run -it --rm debug --image=busybox --restart=Never -n data-processing -- \
  wget -O- http://data-processing-app:8080/health
```

### Check Metrics

```bash
# HAProxy metrics
kubectl port-forward -n data-processing svc/haproxy-ingress-stats 9101:9101
# Visit http://localhost:9101/metrics

# Application metrics
kubectl port-forward -n data-processing svc/data-processing-app 9090:9090
# Visit http://localhost:9090/metrics

# HAProxy stats page
kubectl port-forward -n data-processing svc/haproxy-ingress-stats 1024:1024
# Visit http://localhost:1024/stats
```

## Scaling

### Manual Scaling

```bash
# Scale HAProxy Ingress
kubectl scale deployment haproxy-ingress-controller -n data-processing --replicas=5

# Scale application
kubectl scale deployment data-processing-app -n data-processing --replicas=10
```

### Horizontal Pod Autoscaler

HPA is configured to scale automatically based on:
- CPU utilization (70% for HAProxy, 75% for app)
- Memory utilization (80% for HAProxy, 85% for app)
- Custom metrics (if Prometheus Adapter is configured)

View HPA status:

```bash
kubectl get hpa -n data-processing -w
kubectl describe hpa data-processing-app-hpa -n data-processing
```

### Vertical Pod Autoscaler

VPA is configured in "Off" mode to provide recommendations:

```bash
kubectl describe vpa data-processing-app-vpa -n data-processing
```

## Security

### RBAC

- Minimal permissions following least-privilege principle
- Separate service accounts for HAProxy and application
- ClusterRole for HAProxy (requires cluster-wide ingress access)
- Namespace-scoped Role for application

### Network Policies

Default deny-all policies with explicit allow rules:

- HAProxy: Allow ingress from internet, egress to backends
- Application: Allow ingress from HAProxy, egress to required services
- Monitoring: Allow Prometheus to scrape metrics
- DNS: Allow DNS resolution for all pods

Test network policies:

```bash
# Should succeed (allowed)
kubectl run -it --rm test --image=busybox --restart=Never -n data-processing -- \
  wget -O- http://data-processing-app:8080/health

# Should fail (blocked)
kubectl run -it --rm test --image=busybox --restart=Never -n default -- \
  wget -O- http://data-processing-app.data-processing.svc.cluster.local:8080/health --timeout=5
```

### Pod Security

- Non-root user execution
- Read-only root filesystem
- Dropped all capabilities (except NET_BIND_SERVICE for HAProxy)
- Seccomp profile enabled
- No privilege escalation

### Secrets Management

Using External Secrets Operator for secure secret management:

```bash
# Check External Secrets status
kubectl get externalsecret -n data-processing
kubectl describe externalsecret haproxy-tls-cert -n data-processing

# View generated secrets (without revealing values)
kubectl get secret -n data-processing
```

## Storage

### HostPath Storage

Data is stored on node local storage:

- HAProxy: `/var/lib/haproxy-ingress`
- Application: `/mnt/data-processing`

**Note**: HostPath storage ties pods to specific nodes. For production, consider:
- Using PersistentVolumes with cloud storage (EBS, GCS, Azure Disk)
- Implementing backup strategies
- Ensuring proper node affinity

## Monitoring and Observability

### Prometheus Metrics

All components expose Prometheus metrics:

- HAProxy: Port 9101, path `/metrics`
- Application: Port 9090, path `/metrics`

Example Prometheus scrape config:

```yaml
scrape_configs:
  - job_name: 'haproxy-ingress'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - data-processing
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: haproxy-ingress
        action: keep
      - source_labels: [__meta_kubernetes_pod_container_port_number]
        regex: "9101"
        action: keep

  - job_name: 'data-processing-app'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - data-processing
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: data-processing
        action: keep
```

### Logging

Application logs are written to stdout in JSON format and can be collected by:

- Fluentd/Fluent Bit
- Promtail (for Loki)
- Filebeat (for Elasticsearch)

Example log query:

```bash
# Using kubectl
kubectl logs -n data-processing -l app=data-processing --tail=100 | jq .

# Using stern (if installed)
stern -n data-processing data-processing
```

### Tracing

Application is configured for distributed tracing:

- Trace headers are propagated through HAProxy
- Configure tracing backend (Jaeger, Zipkin, etc.) in application

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n data-processing

# Describe pod for events
kubectl describe pod <pod-name> -n data-processing

# Check resource quotas
kubectl describe resourcequota -n data-processing

# Check if image can be pulled
kubectl get events -n data-processing --sort-by='.lastTimestamp'
```

### Network Issues

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -n data-processing -- \
  nslookup data-processing-app

# Check network policies
kubectl describe networkpolicy -n data-processing

# Temporarily disable network policies (for debugging only)
kubectl delete networkpolicy default-deny-ingress -n data-processing
```

### HPA Not Scaling

```bash
# Check metrics-server
kubectl get deployment metrics-server -n kube-system

# Check HPA status
kubectl describe hpa data-processing-app-hpa -n data-processing

# Check current metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/data-processing/pods
```

### Ingress Issues

```bash
# Check ingress status
kubectl describe ingress data-processing-ingress -n data-processing

# Check HAProxy logs
kubectl logs -n data-processing -l app=haproxy-ingress --tail=100

# Check service endpoints
kubectl get endpoints -n data-processing
```

## Maintenance

### Rolling Updates

```bash
# Update image version
kubectl set image deployment/data-processing-app \
  data-processor=your-registry.example.com/data-processing:1.1.0 \
  -n data-processing

# Monitor rollout
kubectl rollout status deployment/data-processing-app -n data-processing

# Rollback if needed
kubectl rollout undo deployment/data-processing-app -n data-processing
```

### Node Drain

Pod Disruption Budgets ensure availability during node maintenance:

```bash
# Drain node safely
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Pods will be rescheduled respecting PDB constraints
kubectl get pdb -n data-processing
```

### Backup and Restore

```bash
# Backup all manifests
kubectl get all,configmap,secret,ingress,hpa,pdb,networkpolicy \
  -n data-processing -o yaml > backup.yaml

# Backup data (if using HostPath)
# SSH to nodes and backup /var/lib/haproxy-ingress and /mnt/data-processing
```

## Environment-Specific Overlays

Create environment-specific customizations using Kustomize:

```bash
# Directory structure
mkdir -p overlays/{development,staging,production}

# Development overlay
cat > overlays/development/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../
nameSuffix: -dev
replicas:
  - name: haproxy-ingress-controller
    count: 2
  - name: data-processing-app
    count: 2
images:
  - name: your-registry.example.com/data-processing
    newTag: dev-latest
EOF

# Deploy development environment
kubectl apply -k overlays/development/
```

## Performance Tuning

### Resource Optimization

Monitor resource usage and adjust requests/limits:

```bash
# Check actual resource usage
kubectl top pods -n data-processing

# Get VPA recommendations
kubectl describe vpa data-processing-app-vpa -n data-processing
```

### HAProxy Tuning

Adjust HAProxy settings in `configmap.yaml`:

- `max-connections`: Increase for high traffic
- `timeout-*`: Adjust based on application needs
- `balance-algorithm`: Change load balancing strategy

### Application Tuning

Update application configuration in `configmap.yaml`:

- `WORKER_THREADS`: Adjust based on CPU cores
- `BATCH_SIZE`: Optimize for data processing efficiency
- `POOL_SIZE`: Tune database connection pooling

## Cost Optimization

1. **Right-size resources**: Use VPA recommendations
2. **Adjust HPA**: Set appropriate min/max replicas
3. **Use spot instances**: Add node tolerations for spot nodes
4. **Implement cluster autoscaler**: Scale nodes with workload
5. **Monitor idle resources**: Use kube-resource-report

## Security Best Practices

- [ ] Rotate secrets regularly
- [ ] Enable pod security admission
- [ ] Scan images for vulnerabilities
- [ ] Implement runtime security (Falco)
- [ ] Use service mesh for mTLS (optional)
- [ ] Regular security audits (kube-bench, kube-hunter)
- [ ] Implement OPA/Gatekeeper policies

## Support and Documentation

- Internal Documentation: https://docs.example.com/data-processing
- Runbook: https://runbook.example.com/data-processing
- On-call: platform-team@example.com
- Slack: #platform-engineering

## License

Internal use only - Copyright © 2026 Example Corp
