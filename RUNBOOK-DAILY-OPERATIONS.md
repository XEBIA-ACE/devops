# Bacula Backup System - Daily Operations Runbook

## Table of Contents
1. [Daily Health Checks](#daily-health-checks)
2. [Monitoring Dashboard](#monitoring-dashboard)
3. [Common Operational Tasks](#common-operational-tasks)
4. [Troubleshooting](#troubleshooting)
5. [Maintenance Windows](#maintenance-windows)

## Daily Health Checks

### Morning Checklist (15 minutes)

#### 1. Check Overnight Backup Status
```bash
# Connect to Bacula Director
kubectl exec -it -n backup deployment/bacula-director -- bconsole

# In bconsole:
*list jobs last=10
*status dir
*status client
*status storage
```

**Expected Output:**
- All jobs show "OK" status
- No errors in recent job logs
- All clients are connected
- Storage daemons are online

#### 2. Verify Kubernetes CronJobs
```bash
# Check CronJob execution status
kubectl get cronjobs -n backup
kubectl get jobs -n backup --sort-by=.status.startTime

# Check for failed jobs
kubectl get jobs -n backup --field-selector status.successful=0

# View logs of failed jobs (if any)
kubectl logs -n backup job/<job-name>
```

**Action Items:**
- If jobs failed: Investigate logs and re-run manually if needed
- If no jobs ran: Check CronJob schedule and cluster time

#### 3. Monitor Backup Storage Usage
```bash
# Check PVC usage
kubectl exec -n backup deployment/bacula-sd-azure -- df -h /mnt/azure-blob

# Check Azure Blob Storage
az storage blob list --account-name <account> --container-name bacula-backups --query "[].properties.contentLength" --output table | awk '{sum+=$1} END {print sum/1024/1024/1024" GB"}'

# Check AWS S3 bucket size
aws s3 ls s3://bacula-backups --recursive --summarize | grep "Total Size"
```

**Thresholds:**
- Warning: >80% capacity used
- Critical: >90% capacity used
- Action: Trigger retention cleanup or expand storage

#### 4. Review Prometheus Alerts
```bash
# Check for active alerts
kubectl get prometheusrules -n backup bacula-alerts -o yaml

# Query Prometheus for backup metrics
curl -s 'http://prometheus:9090/api/v1/query?query=bacula_job_status' | jq .
```

**Alert Priority:**
- Critical: Respond within 1 hour
- Warning: Review and plan resolution within 4 hours
- Info: Review during regular hours

### Backup Job Verification Checklist

| Check | Command | Expected Result |
|-------|---------|----------------|
| PostgreSQL Backup | `ls -lh /backup/postgres-dump/*.sql.gz \| tail -1` | File created within last 24h |
| MySQL Backup | `ls -lh /backup/mysql-dump/*.sql.gz \| tail -1` | File created within last 24h |
| etcd Snapshot | `ls -lh /backup/etcd-snapshot/*.db.gz \| tail -1` | File created within last 24h |
| PV Backups | Check Bacula job list | All PV jobs completed OK |
| Backup Integrity | Run verification script | All checksums match |

## Monitoring Dashboard

### Grafana Dashboard Access
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Access: http://localhost:3000
# Dashboard: "Bacula Backup System"
```

### Key Metrics to Monitor

#### 1. Backup Success Rate (Target: >99%)
- Metric: `bacula_backup_success_rate_24h`
- Alert if: < 95% for 2 hours

#### 2. Backup Duration
- Full Backup: < 4 hours (RTO target)
- Incremental: < 30 minutes
- Alert if: Exceeds 6 hours

#### 3. Backup Size Trends
- Monitor for unexpected size changes (>50% deviation)
- Track weekly growth rate
- Forecast storage needs

#### 4. Storage Health
- Available space: > 20%
- I/O latency: < 100ms
- Network throughput: > 100 MB/s

## Common Operational Tasks

### Task 1: Manually Trigger Backup Job

```bash
# Using bconsole
kubectl exec -it -n backup deployment/bacula-director -- bconsole

*run job=K8s-PV-Production level=Full
# Confirm: yes

# Monitor job progress
*status dir
*list jobs last=1

# View job details
*list jobid=<job-id>
```

### Task 2: Check Backup Job Logs

```bash
# View Bacula Director logs
kubectl logs -n backup deployment/bacula-director --tail=100

# View File Daemon logs
kubectl logs -n backup daemonset/bacula-fd --tail=100

# View Storage Daemon logs
kubectl logs -n backup deployment/bacula-sd-azure --tail=100

# Check application-specific backup logs
kubectl exec -n backup deployment/bacula-director -- tail -100 /var/log/bacula/postgres-backup.log
kubectl exec -n backup deployment/bacula-director -- tail -100 /var/log/bacula/mysql-backup.log
```

### Task 3: Verify Latest Backup Integrity

```bash
# Run automated verification
kubectl create job --from=cronjob/backup-verification backup-verify-manual -n backup

# Monitor verification
kubectl logs -n backup job/backup-verify-manual -f

# Manual verification using bconsole
kubectl exec -it -n backup deployment/bacula-director -- bconsole

*run job=VerifyBackup level=Catalog
# Select job to verify
```

### Task 4: Check Retention Policy Compliance

```bash
# List volumes and retention
kubectl exec -it -n backup deployment/bacula-director -- bconsole

*list volumes
*list media pool=Father-Pool
*list media pool=Grandfather-Pool

# Check volume expiration
*update volume=<volume-name> volstatus=Recycle
```

**Retention Verification:**
- Son Pool: 14 days (daily backups)
- Father Pool: 56 days (weekly backups)
- Grandfather Pool: 365 days (monthly backups)

### Task 5: Rotate Encryption Keys (Quarterly)

```bash
# Run key rotation script
kubectl exec -n backup deployment/bacula-director -- /opt/bacula/scripts/rotate-keys.sh

# Verify new keys
kubectl exec -n backup deployment/bacula-director -- /opt/bacula/scripts/verify-encryption.sh

# Update Kubernetes secrets
kubectl delete secret bacula-pki-master -n backup
kubectl create secret generic bacula-pki-master \
  --from-file=master.pem=/tmp/new-master.pem \
  --from-file=master-public.pem=/tmp/new-master-public.pem \
  -n backup

# Restart Bacula components
kubectl rollout restart deployment/bacula-director -n backup
kubectl rollout restart daemonset/bacula-fd -n backup
```

## Troubleshooting

### Issue 1: Backup Job Stuck or Hanging

**Symptoms:**
- Job running for >6 hours
- No progress in bconsole status
- High CPU usage on File Daemon

**Diagnosis:**
```bash
# Check job status
kubectl exec -it -n backup deployment/bacula-director -- bconsole
*status dir
*status client=<client-name>

# Check File Daemon logs
kubectl logs -n backup daemonset/bacula-fd --tail=200 | grep ERROR

# Check for filesystem issues
kubectl exec -n backup -c file-daemon daemonset/bacula-fd -- df -h
```

**Resolution:**
```bash
# Cancel stuck job
*cancel jobid=<job-id>

# Restart File Daemon
kubectl rollout restart daemonset/bacula-fd -n backup

# Re-run job
*run job=<job-name> yes
```

### Issue 2: Storage Capacity Full

**Symptoms:**
- Backup jobs failing with "No space left on device"
- Alert: BaculaStorageCapacityCritical

**Diagnosis:**
```bash
# Check PVC usage
kubectl exec -n backup deployment/bacula-sd-azure -- df -h

# Check Bacula volumes
kubectl exec -it -n backup deployment/bacula-director -- bconsole
*list volumes
```

**Resolution:**
```bash
# Option 1: Prune old volumes
*prune files client=<client-name>
*prune jobs client=<client-name>
*prune volume=<volume-name>

# Option 2: Expand PVC
kubectl patch pvc bacula-azure-storage -n backup -p '{"spec":{"resources":{"requests":{"storage":"2Ti"}}}}'

# Option 3: Move old backups to archive tier (Azure)
az storage blob set-tier --account-name <account> --container-name bacula-backups --name <blob-name> --tier Archive

# Option 4: Delete very old incremental backups
find /mnt/azure-blob -name "Inc-*" -mtime +7 -delete
```

### Issue 3: Database Backup Failing

**Symptoms:**
- PostgreSQL/MySQL backup CronJob failing
- Error: "Connection refused" or "Authentication failed"

**Diagnosis:**
```bash
# Check database connectivity
kubectl exec -n backup deployment/bacula-director -- pg_isready -h postgres-service.production.svc.cluster.local

# Test credentials
kubectl get secret postgres-credentials -n backup -o jsonpath='{.data.password}' | base64 -d

# Check database logs
kubectl logs -n production deployment/postgres --tail=100
```

**Resolution:**
```bash
# Update credentials if changed
kubectl create secret generic postgres-credentials \
  --from-literal=username=<new-user> \
  --from-literal=password=<new-pass> \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart backup CronJob
kubectl delete job -n backup $(kubectl get jobs -n backup -l app=postgres-backup -o name)

# Trigger manual run
kubectl create job --from=cronjob/postgres-backup postgres-backup-manual -n backup
```

### Issue 4: TLS Certificate Expired

**Symptoms:**
- Error: "TLS handshake failed"
- Alert: BaculaTLSCertificateExpiringSoon

**Diagnosis:**
```bash
# Check certificate expiration
kubectl exec -n backup deployment/bacula-director -- openssl x509 -in /etc/bacula/ssl/director.crt -noout -dates
```

**Resolution:**
```bash
# Regenerate certificates
kubectl exec -n backup deployment/bacula-director -- /opt/bacula/scripts/generate-tls-certs.sh

# Update Kubernetes secret
kubectl delete secret bacula-tls-certs -n backup
kubectl create secret generic bacula-tls-certs \
  --from-file=/etc/bacula/ssl/ \
  -n backup

# Restart all Bacula components
kubectl rollout restart deployment/bacula-director -n backup
kubectl rollout restart deployment/bacula-sd-azure -n backup
kubectl rollout restart daemonset/bacula-fd -n backup
```

## Maintenance Windows

### Weekly Maintenance (Sunday 2:00 AM - 4:00 AM)

**Tasks:**
1. Verify all weekly Full backups completed
2. Run backup integrity verification
3. Review and clean up old log files
4. Check certificate expiration dates
5. Review storage growth trends
6. Update documentation with any changes

**Script:**
```bash
#!/bin/bash
# weekly-maintenance.sh

echo "=== Weekly Maintenance Started ==="

# 1. Verify backups
kubectl exec -n backup deployment/bacula-director -- bconsole <<EOF
list jobs last=50
quit
EOF

# 2. Run verification
kubectl create job --from=cronjob/backup-verification weekly-verify -n backup

# 3. Clean up logs
kubectl exec -n backup deployment/bacula-director -- find /var/log/bacula -name "*.log" -mtime +30 -delete

# 4. Check certificates
kubectl exec -n backup deployment/bacula-director -- /opt/bacula/scripts/verify-encryption.sh

# 5. Generate weekly report
kubectl exec -n backup deployment/bacula-director -- /opt/bacula/scripts/generate-weekly-report.sh

echo "=== Weekly Maintenance Completed ==="
```

### Monthly Maintenance (First Sunday of Month)

**Tasks:**
1. Perform restore test (DR drill)
2. Rotate encryption keys (if scheduled)
3. Review and update retention policies
4. Audit backup coverage
5. Capacity planning review
6. Update disaster recovery documentation

### Quarterly Maintenance

**Tasks:**
1. Full disaster recovery test
2. Security audit of encryption keys
3. Performance optimization review
4. Review and update SLAs
5. Training session for new team members
6. Vendor patch and update review

## Emergency Contacts

| Role | Contact | Escalation Time |
|------|---------|----------------|
| Backup Administrator | backup-admin@company.com | Immediate |
| Database Administrator | dba@company.com | 15 minutes |
| Platform Engineering | platform@company.com | 30 minutes |
| Security Team | security@company.com | For security incidents |
| On-Call Engineer | PagerDuty | 24/7 |

## Escalation Matrix

1. **Level 1** (0-30 min): Backup Administrator investigates
2. **Level 2** (30-60 min): Escalate to Platform Engineering Lead
3. **Level 3** (60+ min): Escalate to Engineering Manager
4. **Critical** (Immediate): Page on-call engineer + notify management

---
**Document Version:** 1.0
**Last Updated:** 2026-01-21
**Next Review:** 2026-04-21
