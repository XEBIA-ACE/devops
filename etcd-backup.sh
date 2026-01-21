#!/bin/bash
#
# etcd Cluster Backup Script
# Creates consistent snapshots of Kubernetes cluster state
#

set -euo pipefail

# Configuration
BACKUP_DIR="/backup/etcd-snapshot"
K8S_RESOURCES_DIR="/backup/k8s-resources"
LOG_FILE="/var/log/bacula/etcd-backup.log"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# etcd configuration
ETCD_ENDPOINTS="${ETCD_ENDPOINTS:-https://127.0.0.1:2379}"
ETCD_CACERT="${ETCD_CACERT:-/etc/kubernetes/pki/etcd/ca.crt}"
ETCD_CERT="${ETCD_CERT:-/etc/kubernetes/pki/etcd/server.crt}"
ETCD_KEY="${ETCD_KEY:-/etc/kubernetes/pki/etcd/server.key}"

# Kubernetes configuration
KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"

# Retention
SNAPSHOT_RETENTION_DAYS=14

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Initialize directories
initialize_directories() {
    mkdir -p "${BACKUP_DIR}" "${K8S_RESOURCES_DIR}"
    log "Backup directories initialized"
}

# Check etcd health
check_etcd_health() {
    log "Checking etcd cluster health"

    if ! etcdctl \
        --endpoints="${ETCD_ENDPOINTS}" \
        --cacert="${ETCD_CACERT}" \
        --cert="${ETCD_CERT}" \
        --key="${ETCD_KEY}" \
        endpoint health; then
        log_error "etcd cluster is not healthy"
        return 1
    fi

    log "etcd cluster is healthy"
    return 0
}

# Create etcd snapshot
create_etcd_snapshot() {
    local snapshot_file="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

    log "Creating etcd snapshot: ${snapshot_file}"

    ETCDCTL_API=3 etcdctl \
        --endpoints="${ETCD_ENDPOINTS}" \
        --cacert="${ETCD_CACERT}" \
        --cert="${ETCD_CERT}" \
        --key="${ETCD_KEY}" \
        snapshot save "${snapshot_file}" \
        2>> "${LOG_FILE}"

    if [[ ! -f "${snapshot_file}" ]]; then
        log_error "Snapshot file not created"
        return 1
    fi

    # Compress snapshot
    gzip "${snapshot_file}"
    log "etcd snapshot created and compressed: ${snapshot_file}.gz"

    return 0
}

# Verify snapshot integrity
verify_snapshot() {
    local snapshot_file="${1}.gz"

    log "Verifying snapshot integrity"

    # Decompress temporarily for verification
    local temp_snapshot="/tmp/etcd-verify-${TIMESTAMP}.db"
    gunzip -c "${snapshot_file}" > "${temp_snapshot}"

    ETCDCTL_API=3 etcdctl \
        --write-out=table \
        snapshot status "${temp_snapshot}" \
        2>> "${LOG_FILE}"

    local status=$?

    rm -f "${temp_snapshot}"

    if [[ ${status} -ne 0 ]]; then
        log_error "Snapshot verification failed"
        return 1
    fi

    log "Snapshot verification successful"
    return 0
}

# Backup Kubernetes resources
backup_k8s_resources() {
    log "Backing up Kubernetes resources"

    if ! command -v kubectl &> /dev/null; then
        log "kubectl not available, skipping K8s resources backup"
        return 0
    fi

    local resource_dir="${K8S_RESOURCES_DIR}/${TIMESTAMP}"
    mkdir -p "${resource_dir}"

    # Backup all namespaces
    kubectl get namespaces -o yaml > "${resource_dir}/namespaces.yaml" 2>/dev/null || true

    # Backup cluster-level resources
    log "Backing up cluster-level resources"
    kubectl get clusterroles -o yaml > "${resource_dir}/clusterroles.yaml" 2>/dev/null || true
    kubectl get clusterrolebindings -o yaml > "${resource_dir}/clusterrolebindings.yaml" 2>/dev/null || true
    kubectl get persistentvolumes -o yaml > "${resource_dir}/persistentvolumes.yaml" 2>/dev/null || true
    kubectl get storageclasses -o yaml > "${resource_dir}/storageclasses.yaml" 2>/dev/null || true
    kubectl get customresourcedefinitions -o yaml > "${resource_dir}/crds.yaml" 2>/dev/null || true

    # Backup namespace-level resources
    local namespaces
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

    for ns in ${namespaces}; do
        log "Backing up namespace: ${ns}"
        local ns_dir="${resource_dir}/namespaces/${ns}"
        mkdir -p "${ns_dir}"

        # Backup key resources in namespace
        kubectl get all -n "${ns}" -o yaml > "${ns_dir}/all.yaml" 2>/dev/null || true
        kubectl get configmaps -n "${ns}" -o yaml > "${ns_dir}/configmaps.yaml" 2>/dev/null || true
        kubectl get secrets -n "${ns}" -o yaml > "${ns_dir}/secrets.yaml" 2>/dev/null || true
        kubectl get pvc -n "${ns}" -o yaml > "${ns_dir}/pvcs.yaml" 2>/dev/null || true
        kubectl get ingresses -n "${ns}" -o yaml > "${ns_dir}/ingresses.yaml" 2>/dev/null || true
        kubectl get networkpolicies -n "${ns}" -o yaml > "${ns_dir}/networkpolicies.yaml" 2>/dev/null || true
        kubectl get serviceaccounts -n "${ns}" -o yaml > "${ns_dir}/serviceaccounts.yaml" 2>/dev/null || true
        kubectl get roles -n "${ns}" -o yaml > "${ns_dir}/roles.yaml" 2>/dev/null || true
        kubectl get rolebindings -n "${ns}" -o yaml > "${ns_dir}/rolebindings.yaml" 2>/dev/null || true
    done

    # Compress all K8s resources
    tar -czf "${K8S_RESOURCES_DIR}/k8s-resources-${TIMESTAMP}.tar.gz" -C "${K8S_RESOURCES_DIR}" "${TIMESTAMP}"
    rm -rf "${resource_dir}"

    log "Kubernetes resources backup completed"
}

# Create backup metadata
create_metadata() {
    local etcd_version
    etcd_version=$(etcdctl version 2>/dev/null | head -1 || echo "unknown")

    local k8s_version
    k8s_version=$(kubectl version --short 2>/dev/null | grep Server || echo "unknown")

    cat > "${BACKUP_DIR}/etcd-${TIMESTAMP}.meta" <<EOF
Backup Timestamp: ${TIMESTAMP}
etcd Version: ${etcd_version}
Kubernetes Version: ${k8s_version}
etcd Endpoints: ${ETCD_ENDPOINTS}
Snapshot File: etcd-snapshot-${TIMESTAMP}.db.gz
K8s Resources: k8s-resources-${TIMESTAMP}.tar.gz
EOF

    log "Metadata created"
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up backups older than ${SNAPSHOT_RETENTION_DAYS} days"

    find "${BACKUP_DIR}" -name "etcd-snapshot-*.db.gz" -mtime +${SNAPSHOT_RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_DIR}" -name "etcd-*.meta" -mtime +${SNAPSHOT_RETENTION_DAYS} -delete 2>/dev/null || true
    find "${K8S_RESOURCES_DIR}" -name "k8s-resources-*.tar.gz" -mtime +${SNAPSHOT_RETENTION_DAYS} -delete 2>/dev/null || true

    log "Cleanup completed"
}

# Calculate statistics
calculate_stats() {
    log "Calculating backup statistics"

    local snapshot_size
    snapshot_size=$(du -sh "${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db.gz" | cut -f1)

    local k8s_size="0"
    if [[ -f "${K8S_RESOURCES_DIR}/k8s-resources-${TIMESTAMP}.tar.gz" ]]; then
        k8s_size=$(du -sh "${K8S_RESOURCES_DIR}/k8s-resources-${TIMESTAMP}.tar.gz" | cut -f1)
    fi

    cat > "${BACKUP_DIR}/stats-${TIMESTAMP}.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "snapshot_size": "${snapshot_size}",
  "k8s_resources_size": "${k8s_size}",
  "etcd_endpoints": "${ETCD_ENDPOINTS}"
}
EOF

    log "Backup statistics: Snapshot=${snapshot_size}, K8s Resources=${k8s_size}"
}

# Main execution
main() {
    log "=== etcd Backup Started ==="

    # Initialize
    initialize_directories

    # Check etcd health
    check_etcd_health || {
        log_error "etcd health check failed"
        exit 1
    }

    # Create snapshot
    create_etcd_snapshot || {
        log_error "etcd snapshot creation failed"
        exit 1
    }

    # Verify snapshot
    verify_snapshot "${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db" || {
        log_error "Snapshot verification failed"
        exit 1
    }

    # Backup Kubernetes resources
    backup_k8s_resources

    # Create metadata
    create_metadata

    # Calculate statistics
    calculate_stats

    # Cleanup old backups
    cleanup_old_backups

    log "=== etcd Backup Completed Successfully ==="
    exit 0
}

# Error handler
trap 'log_error "etcd backup failed at line $LINENO"; exit 1' ERR

# Execute main
main "$@"
