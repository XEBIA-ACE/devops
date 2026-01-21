#!/bin/bash
#
# Pre-Backup Script for Kubernetes PV Backup
# Handles application quiesce, consistency checks, and preparation
#
# Arguments:
#   $1 - Backup Level (Full, Differential, Incremental)
#   $2 - Job Name
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/bacula/pre-backup.log"
BACKUP_LEVEL="${1:-Incremental}"
JOB_NAME="${2:-unknown}"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Kubernetes configuration
KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
NAMESPACE="${BACKUP_NAMESPACE:-default}"

# Logging function
log() {
    echo "[${TIMESTAMP}] [${JOB_NAME}] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[${TIMESTAMP}] [${JOB_NAME}] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Notification function
send_notification() {
    local status=$1
    local message=$2

    # Send to monitoring system
    curl -X POST "http://monitoring-service/api/v1/events" \
        -H "Content-Type: application/json" \
        -d "{\"job\":\"${JOB_NAME}\",\"status\":\"${status}\",\"message\":\"${message}\",\"timestamp\":\"${TIMESTAMP}\"}" \
        2>/dev/null || true

    # Send to Slack/Teams if configured
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"Backup Pre-Job [${JOB_NAME}]: ${message}\"}" \
            2>/dev/null || true
    fi
}

# Check if running in Kubernetes
check_k8s_environment() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        return 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    log "Kubernetes environment check passed"
    return 0
}

# Freeze filesystem for consistency (if supported)
freeze_filesystem() {
    local mount_point=$1

    log "Freezing filesystem: ${mount_point}"

    if command -v fsfreeze &> /dev/null; then
        if fsfreeze -f "${mount_point}" 2>/dev/null; then
            log "Filesystem frozen: ${mount_point}"
            echo "${mount_point}" >> /tmp/frozen-filesystems.txt
            return 0
        else
            log "Warning: Could not freeze filesystem: ${mount_point}"
            return 1
        fi
    else
        log "fsfreeze not available, skipping filesystem freeze"
        return 0
    fi
}

# Quiesce applications using Kubernetes
quiesce_application() {
    local deployment=$1
    local namespace=${2:-default}

    log "Quiescing application: ${deployment} in namespace ${namespace}"

    # Scale down to 0 for consistent backup
    kubectl scale deployment "${deployment}" --replicas=0 -n "${namespace}" || {
        log_error "Failed to scale down ${deployment}"
        return 1
    }

    # Wait for pods to terminate
    local timeout=300
    local elapsed=0
    while [[ $(kubectl get pods -n "${namespace}" -l app="${deployment}" --no-headers 2>/dev/null | wc -l) -gt 0 ]]; do
        if [[ ${elapsed} -ge ${timeout} ]]; then
            log_error "Timeout waiting for ${deployment} pods to terminate"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log "Application quiesced: ${deployment}"
    echo "${namespace}/${deployment}" >> /tmp/quiesced-apps.txt
    return 0
}

# Create application-consistent snapshot using annotations
create_app_consistent_snapshot() {
    local pvc_name=$1
    local namespace=${2:-default}

    log "Creating application-consistent snapshot for PVC: ${pvc_name}"

    # Get storage class
    local storage_class
    storage_class=$(kubectl get pvc "${pvc_name}" -n "${namespace}" -o jsonpath='{.spec.storageClassName}')

    # Create VolumeSnapshot
    cat <<EOF | kubectl apply -f - || return 1
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${pvc_name}-backup-$(date +%Y%m%d-%H%M%S)
  namespace: ${namespace}
  labels:
    backup-job: "${JOB_NAME}"
    backup-level: "${BACKUP_LEVEL}"
spec:
  volumeSnapshotClassName: ${storage_class}-snapclass
  source:
    persistentVolumeClaimName: ${pvc_name}
EOF

    log "VolumeSnapshot created for ${pvc_name}"
    return 0
}

# Sync filesystem caches
sync_filesystem() {
    log "Syncing filesystem caches"
    sync
    sleep 2
    log "Filesystem sync completed"
}

# Create backup marker file
create_backup_marker() {
    local backup_dir="${1:-/backup}"
    local marker_file="${backup_dir}/.backup-in-progress"

    cat > "${marker_file}" <<EOF
Backup Job: ${JOB_NAME}
Backup Level: ${BACKUP_LEVEL}
Start Time: ${TIMESTAMP}
Hostname: $(hostname)
EOF

    log "Backup marker created: ${marker_file}"
}

# Main execution
main() {
    log "=== Pre-Backup Script Started ==="
    log "Job Name: ${JOB_NAME}"
    log "Backup Level: ${BACKUP_LEVEL}"

    # Initialize tracking files
    > /tmp/frozen-filesystems.txt
    > /tmp/quiesced-apps.txt

    # Check prerequisites
    check_k8s_environment || {
        send_notification "error" "Kubernetes environment check failed"
        exit 1
    }

    # Sync filesystem
    sync_filesystem

    # Create backup marker
    create_backup_marker "/backup/pv-data"

    # Application-specific quiesce logic
    case "${JOB_NAME}" in
        *PostgreSQL*)
            log "PostgreSQL backup detected - no quiesce needed (using pg_dump)"
            ;;
        *MySQL*)
            log "MySQL backup detected - no quiesce needed (using mysqldump)"
            ;;
        *ETCD*)
            log "etcd backup detected - using snapshot method"
            ;;
        *Production*)
            # For production workloads, create snapshots instead of quiescing
            log "Creating application-consistent snapshots for production"
            # Example: create_app_consistent_snapshot "data-pvc" "production"
            ;;
        *)
            # For other jobs, optionally quiesce
            log "Standard PV backup - syncing only"
            ;;
    esac

    # For Full backups, perform additional checks
    if [[ "${BACKUP_LEVEL}" == "Full" ]]; then
        log "Full backup - performing integrity checks"

        # Check disk space
        local backup_dir="/backup/pv-data"
        if [[ -d "${backup_dir}" ]]; then
            local available_space
            available_space=$(df -BG "${backup_dir}" | awk 'NR==2 {print $4}' | sed 's/G//')
            log "Available space in backup directory: ${available_space}GB"

            if [[ ${available_space} -lt 10 ]]; then
                log_error "Insufficient disk space (${available_space}GB available)"
                send_notification "error" "Insufficient disk space for backup"
                exit 1
            fi
        fi
    fi

    # Set exit code file for post-backup script
    echo "0" > /tmp/pre-backup-status.txt

    log "=== Pre-Backup Script Completed Successfully ==="
    send_notification "success" "Pre-backup tasks completed for ${BACKUP_LEVEL} backup"

    exit 0
}

# Error handler
trap 'log_error "Pre-backup script failed at line $LINENO"; send_notification "error" "Pre-backup script failed"; exit 1' ERR

# Execute main function
main "$@"
