#!/bin/bash
#
# Post-Backup Script for Kubernetes PV Backup
# Handles cleanup, unfreezing, application resume, and notifications
#
# Arguments:
#   $1 - Backup Level (Full, Differential, Incremental)
#   $2 - Job Name
#   $3 - Job Exit Status (OK, Error, etc.)
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/bacula/post-backup.log"
BACKUP_LEVEL="${1:-Incremental}"
JOB_NAME="${2:-unknown}"
JOB_STATUS="${3:-Unknown}"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Kubernetes configuration
KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"

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
    local job_stats=${3:-}

    # Send to monitoring system
    local payload="{\"job\":\"${JOB_NAME}\",\"status\":\"${status}\",\"message\":\"${message}\",\"timestamp\":\"${TIMESTAMP}\""
    if [[ -n "${job_stats}" ]]; then
        payload="${payload},\"stats\":${job_stats}"
    fi
    payload="${payload}}"

    curl -X POST "http://monitoring-service/api/v1/events" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        2>/dev/null || true

    # Send alert if backup failed
    if [[ "${status}" == "error" ]] || [[ "${JOB_STATUS}" != "OK" ]]; then
        # Send to PagerDuty/OpsGenie if critical
        if [[ -n "${PAGERDUTY_KEY:-}" ]]; then
            curl -X POST "https://events.pagerduty.com/v2/enqueue" \
                -H "Content-Type: application/json" \
                -d "{\"routing_key\":\"${PAGERDUTY_KEY}\",\"event_action\":\"trigger\",\"payload\":{\"summary\":\"Backup Failed: ${JOB_NAME}\",\"severity\":\"error\",\"source\":\"bacula\"}}" \
                2>/dev/null || true
        fi

        # Send to Slack with urgency
        if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
            curl -X POST "${SLACK_WEBHOOK_URL}" \
                -H "Content-Type: application/json" \
                -d "{\"text\":\"⚠️ BACKUP FAILED: ${JOB_NAME}\\nStatus: ${JOB_STATUS}\\nMessage: ${message}\",\"channel\":\"#alerts\"}" \
                2>/dev/null || true
        fi
    else
        # Success notification
        if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
            curl -X POST "${SLACK_WEBHOOK_URL}" \
                -H "Content-Type: application/json" \
                -d "{\"text\":\"✅ Backup Completed: ${JOB_NAME}\\nLevel: ${BACKUP_LEVEL}\\nStatus: ${JOB_STATUS}\"}" \
                2>/dev/null || true
        fi
    fi
}

# Unfreeze filesystems
unfreeze_filesystems() {
    local frozen_file="/tmp/frozen-filesystems.txt"

    if [[ -f "${frozen_file}" ]]; then
        log "Unfreezing filesystems"

        while IFS= read -r mount_point; do
            if [[ -n "${mount_point}" ]]; then
                if fsfreeze -u "${mount_point}" 2>/dev/null; then
                    log "Unfroze filesystem: ${mount_point}"
                else
                    log_error "Failed to unfreeze: ${mount_point}"
                fi
            fi
        done < "${frozen_file}"

        rm -f "${frozen_file}"
    fi
}

# Resume quiesced applications
resume_applications() {
    local quiesced_file="/tmp/quiesced-apps.txt"

    if [[ -f "${quiesced_file}" ]]; then
        log "Resuming quiesced applications"

        while IFS= read -r app_ref; do
            if [[ -n "${app_ref}" ]]; then
                local namespace="${app_ref%/*}"
                local deployment="${app_ref#*/}"

                # Get original replica count (stored during quiesce)
                local replicas=1  # Default to 1 if not stored

                log "Scaling up ${deployment} in ${namespace} to ${replicas} replicas"
                kubectl scale deployment "${deployment}" --replicas="${replicas}" -n "${namespace}" || {
                    log_error "Failed to scale up ${deployment}"
                }

                # Wait for pods to be ready
                kubectl wait --for=condition=available --timeout=300s deployment/"${deployment}" -n "${namespace}" || {
                    log_error "Deployment ${deployment} not ready after scaling up"
                }

                log "Application resumed: ${deployment}"
            fi
        done < "${quiesced_file}"

        rm -f "${quiesced_file}"
    fi
}

# Remove backup marker
remove_backup_marker() {
    local backup_dir="${1:-/backup}"
    local marker_file="${backup_dir}/.backup-in-progress"

    if [[ -f "${marker_file}" ]]; then
        rm -f "${marker_file}"
        log "Backup marker removed"
    fi
}

# Collect backup statistics
collect_backup_stats() {
    local stats_file="/tmp/backup-stats-${JOB_NAME}.json"

    # Query Bacula for job statistics
    if command -v bconsole &> /dev/null; then
        cat <<EOF | bconsole -c /etc/bacula/bconsole.conf > /tmp/bacula-output.txt 2>&1 || true
@output /dev/null
status client=$(hostname -f)
@output /tmp/bacula-job-list.txt
list jobs last
quit
EOF

        # Parse statistics (simplified - actual parsing depends on Bacula output format)
        local job_bytes=$(grep -oP 'Bytes: \K[\d,]+' /tmp/bacula-job-list.txt | tail -1 | tr -d ',' || echo "0")
        local job_files=$(grep -oP 'Files: \K[\d,]+' /tmp/bacula-job-list.txt | tail -1 | tr -d ',' || echo "0")

        cat > "${stats_file}" <<EOF
{
  "job_name": "${JOB_NAME}",
  "backup_level": "${BACKUP_LEVEL}",
  "status": "${JOB_STATUS}",
  "bytes": ${job_bytes},
  "files": ${job_files},
  "timestamp": "${TIMESTAMP}"
}
EOF

        log "Backup statistics collected: ${job_bytes} bytes, ${job_files} files"
        echo "${stats_file}"
    else
        echo ""
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files"

    # Remove old backup markers
    find /backup -name ".backup-in-progress" -mtime +1 -delete 2>/dev/null || true

    # Clean up old database dumps (keep last 3)
    find /backup/postgres-dump -name "*.sql.gz" -mtime +3 -delete 2>/dev/null || true
    find /backup/mysql-dump -name "*.sql.gz" -mtime +3 -delete 2>/dev/null || true

    # Clean up old snapshots metadata
    find /backup -name "*.snapshot" -mtime +7 -delete 2>/dev/null || true

    log "Cleanup completed"
}

# Update backup metrics for monitoring
update_backup_metrics() {
    local status=$1
    local stats_file=$2

    # Push metrics to Prometheus pushgateway if available
    if [[ -n "${PUSHGATEWAY_URL:-}" ]] && [[ -f "${stats_file}" ]]; then
        local bytes=$(jq -r '.bytes' "${stats_file}")
        local files=$(jq -r '.files' "${stats_file}")
        local status_code=0
        [[ "${status}" == "success" ]] && status_code=1

        cat <<EOF | curl --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/bacula_backup/instance/$(hostname)" || true
# TYPE bacula_backup_status gauge
bacula_backup_status{job="${JOB_NAME}",level="${BACKUP_LEVEL}"} ${status_code}
# TYPE bacula_backup_bytes gauge
bacula_backup_bytes{job="${JOB_NAME}",level="${BACKUP_LEVEL}"} ${bytes}
# TYPE bacula_backup_files gauge
bacula_backup_files{job="${JOB_NAME}",level="${BACKUP_LEVEL}"} ${files}
# TYPE bacula_backup_timestamp gauge
bacula_backup_timestamp{job="${JOB_NAME}",level="${BACKUP_LEVEL}"} $(date +%s)
EOF
    fi

    # Write metrics to local file for node-exporter textfile collector
    if [[ -d "/var/lib/node_exporter/textfile_collector" ]]; then
        local metrics_file="/var/lib/node_exporter/textfile_collector/bacula_backup.prom"
        cat <<EOF > "${metrics_file}.tmp"
# HELP bacula_backup_last_success_timestamp Last successful backup timestamp
# TYPE bacula_backup_last_success_timestamp gauge
bacula_backup_last_success_timestamp{job="${JOB_NAME}",level="${BACKUP_LEVEL}"} $(date +%s)
EOF
        mv "${metrics_file}.tmp" "${metrics_file}"
    fi
}

# Trigger backup verification job
trigger_verification() {
    if [[ "${BACKUP_LEVEL}" == "Full" ]] && [[ "${JOB_STATUS}" == "OK" ]]; then
        log "Triggering backup verification for Full backup"

        # Schedule verification job
        if command -v bconsole &> /dev/null; then
            cat <<EOF | bconsole -c /etc/bacula/bconsole.conf &
run job=VerifyBackup yes
quit
EOF
            log "Verification job scheduled"
        fi
    fi
}

# Main execution
main() {
    log "=== Post-Backup Script Started ==="
    log "Job Name: ${JOB_NAME}"
    log "Backup Level: ${BACKUP_LEVEL}"
    log "Job Status: ${JOB_STATUS}"

    # Always perform cleanup operations
    unfreeze_filesystems
    resume_applications
    remove_backup_marker "/backup/pv-data"

    # Collect statistics
    local stats_file
    stats_file=$(collect_backup_stats)

    # Cleanup temporary files
    cleanup_temp_files

    # Determine overall status
    local status="success"
    if [[ "${JOB_STATUS}" != "OK" ]]; then
        status="error"
        log_error "Backup job completed with status: ${JOB_STATUS}"
    else
        log "Backup job completed successfully"
    fi

    # Update metrics
    update_backup_metrics "${status}" "${stats_file}"

    # Send notifications
    local stats_json=""
    if [[ -f "${stats_file}" ]]; then
        stats_json=$(cat "${stats_file}")
    fi
    send_notification "${status}" "Backup ${JOB_STATUS}" "${stats_json}"

    # Trigger verification if needed
    trigger_verification

    log "=== Post-Backup Script Completed ==="

    # Exit with appropriate code
    if [[ "${status}" == "error" ]]; then
        exit 1
    else
        exit 0
    fi
}

# Error handler - ensure cleanup happens even on error
trap 'log_error "Post-backup script encountered an error at line $LINENO"; unfreeze_filesystems; resume_applications; exit 1' ERR

# Execute main function
main "$@"
