#!/bin/bash
#
# Kubernetes Persistent Volume Restore Script
# Restores data from Bacula backups to PVCs
#
# Usage: restore-pv.sh [OPTIONS]
#   -j JOB_ID      : Bacula job ID to restore
#   -t TIMESTAMP   : Restore to specific point in time
#   -p PVC_NAME    : Target PVC name
#   -n NAMESPACE   : Target namespace
#   -d RESTORE_DIR : Custom restore directory
#   -v             : Verbose mode
#

set -euo pipefail

# Configuration
LOG_FILE="/var/log/bacula/restore.log"
RESTORE_BASE_DIR="/tmp/bacula-restores"
KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"

# Bacula configuration
BACULA_DIR="/opt/bacula/bin"
BCONSOLE="${BACULA_DIR}/bconsole"
BCONSOLE_CONF="/etc/bacula/bconsole.conf"

# Default values
JOB_ID=""
TIMESTAMP=""
PVC_NAME=""
NAMESPACE="default"
RESTORE_DIR=""
VERBOSE=false

# Logging
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${msg}" | tee -a "${LOG_FILE}"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "${msg}" | tee -a "${LOG_FILE}" >&2
}

# Parse command line arguments
parse_args() {
    while getopts "j:t:p:n:d:vh" opt; do
        case ${opt} in
            j) JOB_ID="${OPTARG}" ;;
            t) TIMESTAMP="${OPTARG}" ;;
            p) PVC_NAME="${OPTARG}" ;;
            n) NAMESPACE="${OPTARG}" ;;
            d) RESTORE_DIR="${OPTARG}" ;;
            v) VERBOSE=true ;;
            h)
                echo "Usage: $0 [OPTIONS]"
                echo "  -j JOB_ID      Bacula job ID to restore"
                echo "  -t TIMESTAMP   Restore to specific point in time (YYYY-MM-DD HH:MM:SS)"
                echo "  -p PVC_NAME    Target PVC name"
                echo "  -n NAMESPACE   Target namespace (default: default)"
                echo "  -d RESTORE_DIR Custom restore directory"
                echo "  -v             Verbose mode"
                echo "  -h             Show this help"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites"

    # Check bconsole
    if [[ ! -x "${BCONSOLE}" ]]; then
        log_error "bconsole not found or not executable: ${BCONSOLE}"
        return 1
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        return 1
    fi

    # Check Kubernetes connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    log "Prerequisites validation passed"
    return 0
}

# List available backups
list_available_backups() {
    log "Listing available backups"

    cat <<EOF | "${BCONSOLE}" -c "${BCONSOLE_CONF}"
@output /tmp/bacula-jobs-list.txt
list jobs
quit
EOF

    if [[ -f /tmp/bacula-jobs-list.txt ]]; then
        cat /tmp/bacula-jobs-list.txt
        log "Backup list saved to /tmp/bacula-jobs-list.txt"
    fi
}

# Select backup job interactively
select_backup_job() {
    if [[ -z "${JOB_ID}" ]]; then
        log "No job ID specified. Listing recent backups..."

        cat <<EOF | "${BCONSOLE}" -c "${BCONSOLE_CONF}"
@output /tmp/bacula-recent-jobs.txt
list jobs last=20
quit
EOF

        if [[ -f /tmp/bacula-recent-jobs.txt ]]; then
            cat /tmp/bacula-recent-jobs.txt

            echo ""
            read -rp "Enter Job ID to restore: " JOB_ID
        else
            log_error "Could not list recent jobs"
            return 1
        fi
    fi

    log "Selected Job ID: ${JOB_ID}"
    return 0
}

# Verify backup job exists
verify_backup_job() {
    local job_id=$1

    log "Verifying backup job ${job_id}"

    cat <<EOF | "${BCONSOLE}" -c "${BCONSOLE_CONF}"
@output /tmp/bacula-job-info.txt
list jobid=${job_id}
quit
EOF

    if ! grep -q "JobId.*${job_id}" /tmp/bacula-job-info.txt 2>/dev/null; then
        log_error "Job ID ${job_id} not found"
        return 1
    fi

    log "Backup job verified"
    cat /tmp/bacula-job-info.txt | tee -a "${LOG_FILE}"
    return 0
}

# Prepare restore directory
prepare_restore_directory() {
    if [[ -z "${RESTORE_DIR}" ]]; then
        RESTORE_DIR="${RESTORE_BASE_DIR}/restore-$(date +%Y%m%d-%H%M%S)"
    fi

    log "Preparing restore directory: ${RESTORE_DIR}"

    mkdir -p "${RESTORE_DIR}"

    log "Restore directory ready"
}

# Perform Bacula restore
perform_bacula_restore() {
    local job_id=$1
    local restore_dir=$2

    log "Starting Bacula restore from Job ID ${job_id} to ${restore_dir}"

    # Create Bacula restore script
    local restore_script="/tmp/bacula-restore-${job_id}.bsr"

    if [[ -n "${TIMESTAMP}" ]]; then
        log "Restoring to point-in-time: ${TIMESTAMP}"

        cat <<EOF | "${BCONSOLE}" -c "${BCONSOLE_CONF}"
@output /tmp/bacula-restore-output.txt
restore jobid=${job_id} where=${restore_dir} before="${TIMESTAMP}" all yes
wait
messages
quit
EOF
    else
        cat <<EOF | "${BCONSOLE}" -c "${BCONSOLE_CONF}"
@output /tmp/bacula-restore-output.txt
restore jobid=${job_id} where=${restore_dir} all yes
wait
messages
quit
EOF
    fi

    # Check restore status
    if grep -qi "error" /tmp/bacula-restore-output.txt; then
        log_error "Restore operation reported errors"
        cat /tmp/bacula-restore-output.txt | tee -a "${LOG_FILE}"
        return 1
    fi

    log "Bacula restore completed successfully"
    cat /tmp/bacula-restore-output.txt | tee -a "${LOG_FILE}"

    return 0
}

# Verify restored data
verify_restored_data() {
    local restore_dir=$1

    log "Verifying restored data in ${restore_dir}"

    # Check if directory exists and has content
    if [[ ! -d "${restore_dir}" ]]; then
        log_error "Restore directory not found: ${restore_dir}"
        return 1
    fi

    local file_count
    file_count=$(find "${restore_dir}" -type f | wc -l)

    if [[ ${file_count} -eq 0 ]]; then
        log_error "No files found in restore directory"
        return 1
    fi

    local total_size
    total_size=$(du -sh "${restore_dir}" | cut -f1)

    log "Verification completed: ${file_count} files, ${total_size} total"
    return 0
}

# Copy data to PVC
copy_to_pvc() {
    local source_dir=$1
    local pvc_name=$2
    local namespace=$3

    log "Copying restored data to PVC: ${pvc_name} in namespace ${namespace}"

    # Check if PVC exists
    if ! kubectl get pvc "${pvc_name}" -n "${namespace}" &> /dev/null; then
        log_error "PVC not found: ${pvc_name} in namespace ${namespace}"
        return 1
    fi

    # Create a temporary pod to mount the PVC
    local temp_pod="restore-pod-$(date +%s)"

    log "Creating temporary pod: ${temp_pod}"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${temp_pod}
  namespace: ${namespace}
spec:
  containers:
  - name: restore
    image: busybox:latest
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${pvc_name}
  restartPolicy: Never
EOF

    # Wait for pod to be ready
    log "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready --timeout=300s pod/"${temp_pod}" -n "${namespace}" || {
        log_error "Pod failed to become ready"
        kubectl delete pod "${temp_pod}" -n "${namespace}" --force --grace-period=0 || true
        return 1
    }

    # Copy data to pod
    log "Copying data to pod..."

    # Get the source directory structure (strip the restore base path)
    local source_data="${source_dir}/backup/pv-data"
    if [[ ! -d "${source_data}" ]]; then
        source_data="${source_dir}"
    fi

    # Use kubectl cp to copy data
    kubectl cp "${source_data}/." "${namespace}/${temp_pod}:/data/" || {
        log_error "Failed to copy data to pod"
        kubectl delete pod "${temp_pod}" -n "${namespace}" --force --grace-period=0 || true
        return 1
    }

    # Verify data in pod
    log "Verifying data in PVC..."
    local file_count_pvc
    file_count_pvc=$(kubectl exec "${temp_pod}" -n "${namespace}" -- find /data -type f 2>/dev/null | wc -l)

    log "Files in PVC: ${file_count_pvc}"

    # Delete temporary pod
    log "Cleaning up temporary pod..."
    kubectl delete pod "${temp_pod}" -n "${namespace}" --grace-period=30

    log "Data successfully copied to PVC: ${pvc_name}"
    return 0
}

# Generate restore report
generate_restore_report() {
    local job_id=$1
    local restore_dir=$2
    local pvc_name=$3
    local namespace=$4

    local report_file="${RESTORE_DIR}/restore-report.txt"

    cat > "${report_file}" <<EOF
===========================================
Kubernetes PV Restore Report
===========================================

Restore Date: $(date)
Bacula Job ID: ${job_id}
Point-in-Time: ${TIMESTAMP:-Latest}

Source:
  - Backup Job ID: ${job_id}
  - Restore Directory: ${restore_dir}

Destination:
  - PVC Name: ${pvc_name}
  - Namespace: ${namespace}

Statistics:
  - Files Restored: $(find "${restore_dir}" -type f 2>/dev/null | wc -l)
  - Total Size: $(du -sh "${restore_dir}" 2>/dev/null | cut -f1)

Status: SUCCESS

Next Steps:
  1. Verify application functionality
  2. Check data consistency
  3. Monitor application logs
  4. Clean up restore directory if no longer needed:
     rm -rf ${restore_dir}

===========================================
EOF

    cat "${report_file}" | tee -a "${LOG_FILE}"

    log "Restore report saved to: ${report_file}"
}

# Main execution
main() {
    log "=== Kubernetes PV Restore Started ==="

    # Parse arguments
    parse_args "$@"

    # Validate prerequisites
    validate_prerequisites || {
        log_error "Prerequisites validation failed"
        exit 1
    }

    # Select or verify backup job
    if [[ -z "${JOB_ID}" ]]; then
        select_backup_job || exit 1
    fi

    verify_backup_job "${JOB_ID}" || exit 1

    # Prepare restore directory
    prepare_restore_directory

    # Perform Bacula restore
    perform_bacula_restore "${JOB_ID}" "${RESTORE_DIR}" || {
        log_error "Bacula restore failed"
        exit 1
    }

    # Verify restored data
    verify_restored_data "${RESTORE_DIR}" || {
        log_error "Data verification failed"
        exit 1
    }

    # Copy to PVC if specified
    if [[ -n "${PVC_NAME}" ]]; then
        copy_to_pvc "${RESTORE_DIR}" "${PVC_NAME}" "${NAMESPACE}" || {
            log_error "Failed to copy data to PVC"
            exit 1
        }
    else
        log "No PVC specified. Data restored to: ${RESTORE_DIR}"
        log "To copy to PVC, run: kubectl cp ${RESTORE_DIR} <namespace>/<pod>:/path"
    fi

    # Generate restore report
    generate_restore_report "${JOB_ID}" "${RESTORE_DIR}" "${PVC_NAME}" "${NAMESPACE}"

    log "=== Kubernetes PV Restore Completed Successfully ==="

    exit 0
}

# Error handler
trap 'log_error "Restore failed at line $LINENO"; exit 1' ERR

# Execute main
main "$@"
