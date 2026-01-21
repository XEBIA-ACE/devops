# Disaster Recovery Runbook - Bacula Backup System

## Table of Contents
1. [Emergency Response](#emergency-response)
2. [Recovery Scenarios](#recovery-scenarios)
3. [Recovery Procedures](#recovery-procedures)
4. [Validation Steps](#validation-steps)
5. [Post-Recovery Activities](#post-recovery-activities)

## Emergency Response

### Incident Classification

#### Severity Levels

| Severity | Description | RTO | RPO | Response Time |
|----------|-------------|-----|-----|---------------|
| P0 - Critical | Complete data center failure, total data loss | 7 days | 24 hours | Immediate |
| P1 - High | Single cluster failure, partial data loss | 48 hours | 6 hours | 30 minutes |
| P2 - Medium | Service degradation, no data loss | 7 days | 1 hour | 2 hours |
| P3 - Low | Performance issues, backups affected | 14 days | 24 hours | 4 hours |

### Emergency Contact Procedure

1. **Assess the Situation** (5 minutes)
   - Determine scope and severity
   - Check monitoring dashboards
   - Review recent changes

2. **Notify Stakeholders** (10 minutes)
   ```bash
   # Trigger emergency notification
   curl -X POST https://alerts.company.com/emergency \
     -H "Content-Type: application/json" \
     -d '{"severity":"P0","description":"Data center failure","requester":"<your-name>"}'
   ```

3. **Assemble Recovery Team**
   - Backup Administrator (Lead)
   - Database Administrator
   - Platform Engineer
   - Security Officer
   - Application Owner

4. **Activate War Room**
   - Conference bridge: +1-XXX-XXX-XXXX
   - Slack channel: #incident-response
   - Zoom room: https://zoom.us/j/emergency

## Recovery Scenarios

### Scenario 1: Complete Kubernetes Cluster Failure

**Symptoms:**
- Entire K8s cluster unreachable
- All applications down
- etcd cluster failed

**Impact:**
- All services unavailable
- New data cannot be written
- Existing backups are safe (stored externally)

**Recovery Strategy:** Restore from etcd backup + PV snapshots

---

### Scenario 2: Persistent Volume Data Corruption

**Symptoms:**
- Application reports data inconsistency
- File system errors
- Database corruption

**Impact:**
- Single application affected
- Data integrity compromised
- Service degraded

**Recovery Strategy:** Restore specific PVC from Bacula backup

---

### Scenario 3: Database Complete Loss

**Symptoms:**
- Database pod crashed
- Data directory empty or corrupted
- Cannot restart database

**Impact:**
- Application cannot function
- Data access lost
- Transactions failing

**Recovery Strategy:** Restore from database dump + WAL archives

---

### Scenario 4: Ransomware Attack

**Symptoms:**
- Files encrypted
- Unusual network activity
- Ransom note found

**Impact:**
- Data encrypted/inaccessible
- System compromised
- Possible data exfiltration

**Recovery Strategy:** Isolate systems + restore from immutable backups

---

## Recovery Procedures

### Procedure 1: Full Kubernetes Cluster Recovery

**Prerequisites:**
- New Kubernetes cluster provisioned
- Network connectivity to backup storage
- Credentials and encryption keys available

**Estimated Time:** 4-6 hours

#### Step 1: Restore etcd Cluster (30 minutes)

```bash
# 1. Get latest etcd snapshot
export LATEST_SNAPSHOT=$(kubectl exec -n backup deployment/bacula-director -- \
  ls -t /backup/etcd-snapshot/etcd-snapshot-*.db.gz | head -1)

echo "Restoring from: ${LATEST_SNAPSHOT}"

# 2. Copy snapshot to new etcd node
kubectl cp backup/bacula-director:${LATEST_SNAPSHOT} /tmp/etcd-restore.db.gz

# 3. Decompress snapshot
gunzip /tmp/etcd-restore.db.gz

# 4. Restore etcd data
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-restore.db \
  --name etcd-0 \
  --initial-cluster etcd-0=https://etcd-0:2380 \
  --initial-cluster-token etcd-cluster-1 \
  --initial-advertise-peer-urls https://etcd-0:2380 \
  --data-dir /var/lib/etcd-restore

# 5. Replace etcd data directory
systemctl stop etcd
mv /var/lib/etcd /var/lib/etcd-old
mv /var/lib/etcd-restore /var/lib/etcd
chown -R etcd:etcd /var/lib/etcd
systemctl start etcd

# 6. Verify etcd health
etcdctl endpoint health
etcdctl member list
```

**Validation:**
```bash
# Check cluster state
kubectl get nodes
kubectl get pods --all-namespaces

# Verify critical namespaces
kubectl get ns
```

#### Step 2: Restore Kubernetes Resources (1 hour)

```bash
# 1. Get latest K8s resources backup
export K8S_BACKUP=$(kubectl exec -n backup deployment/bacula-director -- \
  ls -t /backup/k8s-resources/k8s-resources-*.tar.gz | head -1)

# 2. Extract resources
kubectl cp backup/bacula-director:${K8S_BACKUP} /tmp/k8s-resources.tar.gz
tar -xzf /tmp/k8s-resources.tar.gz -C /tmp/

# 3. Restore cluster-level resources
kubectl apply -f /tmp/*/clusterroles.yaml
kubectl apply -f /tmp/*/clusterrolebindings.yaml
kubectl apply -f /tmp/*/storageclasses.yaml
kubectl apply -f /tmp/*/crds.yaml

# 4. Restore namespaces
kubectl apply -f /tmp/*/namespaces.yaml

# 5. Restore namespace-level resources
for ns in /tmp/*/namespaces/*; do
  namespace=$(basename $ns)
  echo "Restoring namespace: ${namespace}"

  # Skip system namespaces
  if [[ "${namespace}" =~ ^(kube-|default) ]]; then
    continue
  fi

  kubectl apply -f ${ns}/ -n ${namespace}
done

# 6. Verify resource restoration
kubectl get all --all-namespaces
```

#### Step 3: Restore Persistent Volumes (2-3 hours)

```bash
# 1. List all PVCs that need restoration
kubectl get pvc --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase

# 2. For each PVC, restore from Bacula
for pvc in $(kubectl get pvc -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"'); do
  namespace=$(echo $pvc | cut -d'/' -f1)
  pvc_name=$(echo $pvc | cut -d'/' -f2)

  echo "Restoring PVC: ${namespace}/${pvc_name}"

  # Find latest backup job for this PVC
  job_id=$(kubectl exec -n backup deployment/bacula-director -- bconsole <<EOF | grep "K8s-PV-${namespace}" | head -1 | awk '{print $1}'
list jobs
quit
EOF
  )

  # Restore PVC using restore script
  kubectl exec -n backup deployment/bacula-director -- \
    /opt/bacula/scripts/restore-pv.sh -j ${job_id} -p ${pvc_name} -n ${namespace}
done

# 3. Verify PVC data
kubectl exec -n production deployment/app-server -- ls -la /data
```

#### Step 4: Restore Databases (1-2 hours)

**PostgreSQL:**
```bash
# 1. Get latest PostgreSQL backup
export PG_BACKUP=$(kubectl exec -n backup deployment/bacula-director -- \
  ls -t /backup/postgres-dump/postgres-all-*.sql.gz | head -1)

# 2. Restore database
kubectl exec -n backup deployment/bacula-director -- \
  /opt/bacula/scripts/restore-database.sh \
  -t postgres \
  -f ${PG_BACKUP} \
  -d production_db \
  -h postgres-service.production.svc.cluster.local \
  -u postgres \
  -n production

# 3. For Point-in-Time Recovery (if needed)
kubectl exec -n backup deployment/bacula-director -- \
  /opt/bacula/scripts/restore-database.sh \
  -t postgres \
  -p "2026-01-21 14:30:00" \
  -h postgres-service.production.svc.cluster.local
```

**MySQL:**
```bash
# 1. Get latest MySQL backup
export MYSQL_BACKUP=$(kubectl exec -n backup deployment/bacula-director -- \
  ls -t /backup/mysql-dump/mysql-all-*.sql.gz | head -1)

# 2. Restore database
kubectl exec -n backup deployment/bacula-director -- \
  /opt/bacula/scripts/restore-database.sh \
  -t mysql \
  -f ${MYSQL_BACKUP} \
  -d production_db \
  -h mysql-service.production.svc.cluster.local \
  -u root \
  -n production
```

#### Step 5: Verify Application Functionality (30 minutes)

```bash
# 1. Check pod status
kubectl get pods --all-namespaces | grep -v "Running\|Completed"

# 2. Check service endpoints
kubectl get endpoints --all-namespaces

# 3. Test application connectivity
curl -k https://app.company.com/health

# 4. Verify database connectivity
kubectl exec -n production deployment/app-server -- \
  psql -h postgres-service -U app_user -d production_db -c "SELECT COUNT(*) FROM users;"

# 5. Run smoke tests
kubectl run smoke-test --image=curlimages/curl --rm -it -- \
  curl -k https://internal-api.company.com/v1/health
```

---

### Procedure 2: Single PVC Restoration

**Prerequisites:**
- Backup job ID or timestamp
- Target PVC and namespace identified
- Application can tolerate downtime

**Estimated Time:** 30-60 minutes

```bash
# 1. Scale down application
kubectl scale deployment app-server -n production --replicas=0

# 2. Wait for pods to terminate
kubectl wait --for=delete pod -l app=app-server -n production --timeout=300s

# 3. Run restore script
kubectl exec -n backup deployment/bacula-director -- \
  /opt/bacula/scripts/restore-pv.sh \
  -j <JOB_ID> \
  -p data-pvc \
  -n production \
  -v

# 4. Verify restored data
kubectl run -n production test-pod --image=busybox --rm -it -- \
  --overrides='{"spec":{"containers":[{"name":"test","image":"busybox","volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"data-pvc"}}]}}' \
  -- ls -la /data

# 5. Scale application back up
kubectl scale deployment app-server -n production --replicas=3

# 6. Monitor application startup
kubectl rollout status deployment/app-server -n production
```

---

### Procedure 3: Database Point-in-Time Recovery (PITR)

**Use Case:** Recover database to specific point before corruption/deletion

**PostgreSQL PITR:**

```bash
# 1. Determine target recovery time
export RECOVERY_TIME="2026-01-21 13:45:00"

# 2. Find base backup before recovery time
kubectl exec -n backup deployment/bacula-director -- \
  ls -lt /backup/postgres-dump/basebackup-* | head -5

export BASE_BACKUP="/backup/postgres-dump/basebackup-20260120-020000"

# 3. Stop PostgreSQL
kubectl scale statefulset postgres -n production --replicas=0

# 4. Run PITR restore
kubectl exec -n backup deployment/bacula-director -- bash <<EOF
# Extract base backup
mkdir -p /tmp/postgres-pitr
tar -xzf ${BASE_BACKUP}/base.tar.gz -C /tmp/postgres-pitr

# Create recovery.conf
cat > /tmp/postgres-pitr/recovery.conf <<RECOVERY
restore_command = 'cp /backup/postgres-wal/%f %p'
recovery_target_time = '${RECOVERY_TIME}'
recovery_target_action = 'promote'
RECOVERY

# Copy to PostgreSQL data directory
kubectl cp /tmp/postgres-pitr production/postgres-0:/var/lib/postgresql/data-new
EOF

# 5. Update PostgreSQL pod to use new data directory
kubectl exec -n production postgres-0 -- bash <<EOF
# Backup old data
mv /var/lib/postgresql/data /var/lib/postgresql/data-old
mv /var/lib/postgresql/data-new /var/lib/postgresql/data
chown -R postgres:postgres /var/lib/postgresql/data
EOF

# 6. Start PostgreSQL
kubectl scale statefulset postgres -n production --replicas=1

# 7. Monitor recovery
kubectl logs -n production postgres-0 -f | grep "recovery"

# 8. Verify recovered data
kubectl exec -n production postgres-0 -- \
  psql -U postgres -c "SELECT max(created_at) FROM transactions;"
```

---

### Procedure 4: Ransomware Recovery

**Critical:** Isolate infected systems IMMEDIATELY

#### Phase 1: Containment (15 minutes)

```bash
# 1. Network isolation
kubectl label namespace production network-policy=isolated

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-infected
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
EOF

# 2. Take snapshots of infected systems (forensics)
kubectl exec -n production pod/infected-pod -- tar -czf /tmp/forensics.tar.gz /var/log /etc /home

# 3. Notify security team
curl -X POST https://security-api.company.com/incident \
  -d '{"type":"ransomware","severity":"critical","namespace":"production"}'

# 4. Preserve evidence
kubectl cp production/infected-pod:/tmp/forensics.tar.gz ./evidence/forensics-$(date +%Y%m%d-%H%M%S).tar.gz
```

#### Phase 2: Assessment (30 minutes)

```bash
# 1. Identify affected resources
kubectl get pods -n production -o wide

# 2. Check backup integrity
kubectl exec -n backup deployment/bacula-director -- \
  /opt/bacula/scripts/verify-backup-integrity.sh

# 3. Determine last known good backup
kubectl exec -n backup deployment/bacula-director -- bconsole <<EOF
list jobs
quit
EOF

# 4. Identify recovery point
# Use backup from BEFORE infection timestamp
export RECOVERY_TIMESTAMP="2026-01-20 18:00:00"
```

#### Phase 3: Recovery (2-4 hours)

```bash
# 1. Create new clean namespace
kubectl create namespace production-clean

# 2. Deploy from infrastructure-as-code (IaC)
kubectl apply -f manifests/ -n production-clean

# 3. Restore data from immutable backup
# Use procedure from "Full Kubernetes Cluster Recovery" above
# Restore to production-clean namespace

# 4. Verify data integrity
kubectl exec -n production-clean deployment/app-server -- \
  /app/scripts/data-integrity-check.sh

# 5. Switch traffic to clean environment
kubectl patch service app-service -n production \
  --patch '{"spec":{"selector":{"namespace":"production-clean"}}}'

# 6. Monitor for re-infection
kubectl logs -n production-clean deployment/app-server -f | grep -i "suspect\|malware\|crypto"
```

#### Phase 4: Security Hardening

```bash
# 1. Rotate all credentials
kubectl delete secret --all -n production-clean
kubectl create secret ...  # Recreate with new credentials

# 2. Update security policies
kubectl apply -f security-policies/pod-security-policy.yaml

# 3. Enable audit logging
kubectl apply -f audit-policy.yaml

# 4. Scan images for vulnerabilities
trivy image --severity HIGH,CRITICAL $(kubectl get pods -n production-clean -o jsonpath='{.items[*].spec.containers[*].image}')
```

---

## Validation Steps

### Post-Recovery Validation Checklist

- [ ] All pods are running and healthy
- [ ] Services are accessible externally
- [ ] Database queries return expected results
- [ ] Application smoke tests pass
- [ ] Monitoring and alerting functional
- [ ] Logs are being collected
- [ ] Backups are resuming normally
- [ ] Performance metrics within normal range
- [ ] Security scans show no vulnerabilities
- [ ] User acceptance testing completed

### Data Integrity Validation

```bash
# 1. Row counts match expected
kubectl exec -n production postgres-0 -- psql -U postgres -c "
  SELECT
    schemaname,
    tablename,
    n_live_tup as row_count
  FROM pg_stat_user_tables
  ORDER BY n_live_tup DESC;
"

# 2. Checksums verification
kubectl exec -n production deployment/app-server -- \
  find /data -type f -exec sha256sum {} \; > /tmp/checksums-post-recovery.txt

diff /tmp/checksums-pre-incident.txt /tmp/checksums-post-recovery.txt

# 3. Application health checks
for endpoint in /health /ready /metrics; do
  curl -f https://app.company.com${endpoint} || echo "FAILED: ${endpoint}"
done
```

---

## Post-Recovery Activities

### 1. Incident Report

**Required within 24 hours:**

```markdown
# Incident Report: [INCIDENT-ID]

## Summary
- Date/Time: YYYY-MM-DD HH:MM:SS
- Duration: X hours
- Severity: PX
- Impact: [Description]

## Timeline
- HH:MM - Incident detected
- HH:MM - Response team assembled
- HH:MM - Recovery initiated
- HH:MM - Service restored
- HH:MM - Validation completed

## Root Cause
[Detailed analysis]

## Recovery Actions
1. [Action 1]
2. [Action 2]

## Data Loss
- RPO Achieved: X hours
- RTO Achieved: X hours
- Data Lost: [None/Description]

## Lessons Learned
- What went well
- What needs improvement

## Action Items
- [ ] Action 1 (Owner: Name, Due: Date)
- [ ] Action 2 (Owner: Name, Due: Date)
```

### 2. Backup System Verification

```bash
# 1. Verify backups are running post-recovery
kubectl get cronjobs -n backup
kubectl get jobs -n backup --sort-by=.status.startTime

# 2. Run full backup of recovered systems
kubectl exec -it -n backup deployment/bacula-director -- bconsole <<EOF
run job=K8s-PV-Production level=Full yes
run job=PostgreSQL-Backup level=Full yes
quit
EOF

# 3. Test restore from new backup
kubectl create job --from=cronjob/backup-verification post-recovery-verify -n backup
```

### 3. Update Documentation

- Update recovery time estimates
- Document any new procedures used
- Update contact information if changed
- Add new scenarios encountered
- Update system architecture diagrams

### 4. Team Debrief

Schedule within 48 hours:
- Review incident timeline
- Discuss what worked / didn't work
- Identify process improvements
- Update runbooks
- Plan training sessions

---

## RTO/RPO Tracking

| Recovery Scenario | Target RTO | Target RPO | Last Drill RTO | Last Drill RPO | Status |
|-------------------|------------|------------|----------------|----------------|--------|
| Full Cluster | 7 days | 24 hours | 5.5 days | 12 hours | ✅ Pass |
| Single PVC | 4 hours | 6 hours | 45 minutes | 3 hours | ✅ Pass |
| Database | 24 hours | 1 hour | 18 hours | 30 minutes | ✅ Pass |
| Ransomware | 48 hours | 24 hours | Not tested | Not tested | ⚠️ Pending |

---

**Document Version:** 1.0
**Last Drill Date:** 2026-01-15
**Next Scheduled Drill:** 2026-04-15
**Document Owner:** Backup Administrator
**Last Updated:** 2026-01-21
