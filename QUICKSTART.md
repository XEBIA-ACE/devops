# Quick Start Guide

Get your data processing application deployed in 5 minutes!

## Prerequisites Check

```bash
# Check Kubernetes access
kubectl cluster-info

# Check required tools
kubectl version --client --short
kustomize version || echo "Will use kubectl with built-in kustomize"

# Check if metrics-server is running (required for HPA)
kubectl get deployment metrics-server -n kube-system
```

## 5-Minute Deployment

### Step 1: Update Required Configuration (2 minutes)

Edit these files with your specific values:

```bash
# 1. Update container image
sed -i 's|your-registry.example.com/data-processing:1.0.0|YOUR_IMAGE:TAG|g' deployment.yaml

# 2. Update domain name
sed -i 's|data-processing.example.com|YOUR_DOMAIN|g' ingress.yaml

# 3. Update cloud provider LoadBalancer annotations
# Edit service.yaml lines 14-23 for your cloud provider (AWS/GCP/Azure)
```

### Step 2: Create Required Secrets (1 minute)

**Option A: Manual Secrets (for testing)**
```bash
# Create TLS certificate (use your own cert and key)
kubectl create secret tls haproxy-tls-secret \
  --cert=/path/to/tls.crt \
  --key=/path/to/tls.key \
  -n data-processing --dry-run=client -o yaml | kubectl apply -f -

# Create application secrets
kubectl create secret generic data-processing-secrets \
  --from-literal=database-password='changeme' \
  --from-literal=api-key='your-api-key' \
  --from-literal=encryption-key='your-encryption-key' \
  -n data-processing --dry-run=client -o yaml | kubectl apply -f -
```

**Option B: External Secrets (for production)**
```bash
# Configure External Secrets Operator SecretStore
# Edit secrets.yaml with your Vault/AWS Secrets Manager details
# The secrets will be automatically synced
```

### Step 3: Deploy Everything (1 minute)

```bash
# Make deployment script executable
chmod +x deploy.sh

# Deploy all resources
./deploy.sh

# Or deploy manually with kubectl
kubectl apply -f namespace.yaml
kubectl apply -f rbac.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secrets.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml
kubectl apply -f pdb.yaml
kubectl apply -f network-policy.yaml

# Or use kustomize
kubectl apply -k .
```

### Step 4: Verify Deployment (1 minute)

```bash
# Check pod status
kubectl get pods -n data-processing

# Expected output:
# NAME                                          READY   STATUS    RESTARTS   AGE
# haproxy-ingress-controller-xxxxxxxxxx-xxxxx   2/2     Running   0          2m
# haproxy-ingress-controller-xxxxxxxxxx-xxxxx   2/2     Running   0          2m
# haproxy-ingress-controller-xxxxxxxxxx-xxxxx   2/2     Running   0          2m
# data-processing-app-xxxxxxxxxx-xxxxx          1/1     Running   0          2m
# data-processing-app-xxxxxxxxxx-xxxxx          1/1     Running   0          2m
# data-processing-app-xxxxxxxxxx-xxxxx          1/1     Running   0          2m

# Check services
kubectl get svc -n data-processing

# Check ingress (wait for ADDRESS to be assigned)
kubectl get ingress -n data-processing

# Test health endpoint
curl -k https://YOUR_DOMAIN/health
```

## Common Quick Fixes

### Pods Stuck in Pending

```bash
# Check resource quotas
kubectl describe resourcequota -n data-processing

# Check node resources
kubectl top nodes

# Check pod events
kubectl describe pod <pod-name> -n data-processing
```

### Pods Stuck in ImagePullBackOff

```bash
# Update image reference in deployment.yaml
# Ensure image is accessible from cluster
# Check image pull secrets if using private registry
```

### Network Policies Blocking Traffic

```bash
# Temporarily remove network policies for debugging
kubectl delete networkpolicy default-deny-ingress -n data-processing
kubectl delete networkpolicy default-deny-egress -n data-processing

# Re-apply after fixing
kubectl apply -f network-policy.yaml
```

### Secrets Not Found

```bash
# Check if secrets exist
kubectl get secrets -n data-processing

# If using External Secrets, check status
kubectl get externalsecret -n data-processing
kubectl describe externalsecret haproxy-tls-cert -n data-processing

# Create manual secrets if needed (see Step 2)
```

## Next Steps

Once deployed, configure monitoring and test your application:

### 1. Configure Monitoring

```bash
# Access HAProxy stats
kubectl port-forward -n data-processing svc/haproxy-ingress-stats 1024:1024
# Visit http://localhost:1024/stats

# Access metrics
kubectl port-forward -n data-processing svc/haproxy-ingress-stats 9101:9101
# Visit http://localhost:9101/metrics

kubectl port-forward -n data-processing svc/data-processing-app 9090:9090
# Visit http://localhost:9090/metrics
```

### 2. Test Autoscaling

```bash
# Watch HPA in action
kubectl get hpa -n data-processing -w

# Generate load (example with Apache Bench)
ab -n 10000 -c 100 https://YOUR_DOMAIN/
```

### 3. Test High Availability

```bash
# Delete a pod and watch it recreate
kubectl delete pod <pod-name> -n data-processing

# Watch rollout with zero downtime
kubectl set image deployment/data-processing-app \
  data-processor=YOUR_IMAGE:NEW_TAG -n data-processing

kubectl rollout status deployment/data-processing-app -n data-processing
```

### 4. Check Logs

```bash
# HAProxy logs
kubectl logs -n data-processing -l app=haproxy-ingress --tail=100 -f

# Application logs
kubectl logs -n data-processing -l app=data-processing --tail=100 -f
```

## Production Checklist

Before going to production, complete these tasks:

- [ ] Use real TLS certificates (not self-signed)
- [ ] Configure External Secrets Operator for secret management
- [ ] Set up proper monitoring (Prometheus + Grafana)
- [ ] Configure alerting (AlertManager)
- [ ] Set up log aggregation (ELK/Loki)
- [ ] Review and adjust resource requests/limits
- [ ] Configure backup strategy for HostPath volumes
- [ ] Test disaster recovery procedures
- [ ] Review security policies with security team
- [ ] Document runbook for on-call team
- [ ] Load test the application
- [ ] Set up CI/CD pipeline

## Resources

- Full documentation: [README.md](README.md)
- Deployment checklist: [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)
- Manifest details: [MANIFEST_SUMMARY.md](MANIFEST_SUMMARY.md)
- Troubleshooting: See README.md "Troubleshooting" section

## Getting Help

- Check pod logs: `kubectl logs -n data-processing <pod-name>`
- Check events: `kubectl get events -n data-processing --sort-by='.lastTimestamp'`
- Describe resources: `kubectl describe <resource> <name> -n data-processing`
- Run verification: `./deploy.sh --verify-only`

## Clean Up

To remove the entire deployment:

```bash
# Delete all resources
kubectl delete namespace data-processing

# Or delete individual resources
kubectl delete -f network-policy.yaml
kubectl delete -f pdb.yaml
kubectl delete -f hpa.yaml
kubectl delete -f ingress.yaml
kubectl delete -f service.yaml
kubectl delete -f deployment.yaml
kubectl delete -f secrets.yaml
kubectl delete -f configmap.yaml
kubectl delete -f rbac.yaml
kubectl delete -f namespace.yaml

# Using kustomize
kubectl delete -k .
```

---

**Ready to deploy?** Run `./deploy.sh` and you're done! 🚀
