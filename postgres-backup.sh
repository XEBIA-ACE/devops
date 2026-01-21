#!/bin/bash
#
# PostgreSQL Backup Script with Point-in-Time Recovery Support
# Creates logical dumps and manages WAL archiving
#
# Arguments:
#   $1 - Backup Level (Full, Differential, Incremental)
#

set -euo pipefail

# Configuration
BACKUP_DIR="/backup/postgres-dump"
WAL_ARCHIVE_DIR="/backup/postgres-wal"
LOG_FILE="/var/log/bacula/postgres-backup.log"
BACKUP_LEVEL="${1:-Full}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# PostgreSQL connection settings (from environment or k8s secrets)
PGHOST="${PGHOST:-postgres-service.default.svc.cluster.local}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-postgres}"
PGPASSWORD="${PGPASSWORD:-}"

# Backup retention for dumps (days)
DUMP_RETENTION_DAYS=7

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Create backup directories
initialize_directories() {
    mkdir -p "${BACKUP_DIR}" "${WAL_ARCHIVE_DIR}"
    log "Backup directories initialized"
}

# Test PostgreSQL connection
test_connection() {
    log "Testing PostgreSQL connection to ${PGHOST}:${PGPORT}"

    if ! PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -c "SELECT version();" > /dev/null 2>&1; then
        log_error "Cannot connect to PostgreSQL server"
        return 1
    fi

    log "PostgreSQL connection successful"
    return 0
}

# Perform pg_dump (logical backup)
perform_logical_backup() {
    local dump_file="${BACKUP_DIR}/postgres-${TIMESTAMP}.sql"
    local compressed_file="${dump_file}.gz"

    log "Starting logical backup: ${dump_file}"

    # Get list of databases
    local databases
    databases=$(PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" | grep -v '^$')

    # Backup globals (roles, tablespaces)
    log "Backing up global objects"
    PGPASSWORD="${PGPASSWORD}" pg_dumpall -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" --globals-only | gzip > "${BACKUP_DIR}/postgres-globals-${TIMESTAMP}.sql.gz"

    # Backup each database
    for db in ${databases}; do
        log "Backing up database: ${db}"

        PGPASSWORD="${PGPASSWORD}" pg_dump \
            -h "${PGHOST}" \
            -p "${PGPORT}" \
            -U "${PGUSER}" \
            -d "${db}" \
            --format=custom \
            --compress=9 \
            --verbose \
            --file="${BACKUP_DIR}/postgres-${db}-${TIMESTAMP}.dump" \
            2>> "${LOG_FILE}"

        # Create a SQL version for portability
        PGPASSWORD="${PGPASSWORD}" pg_dump \
            -h "${PGHOST}" \
            -p "${PGPORT}" \
            -U "${PGUSER}" \
            -d "${db}" \
            --format=plain \
            --verbose \
            2>> "${LOG_FILE}" | gzip > "${BACKUP_DIR}/postgres-${db}-${TIMESTAMP}.sql.gz"

        log "Database ${db} backed up successfully"
    done

    # Create metadata file
    cat > "${BACKUP_DIR}/postgres-${TIMESTAMP}.meta" <<EOF
Backup Timestamp: ${TIMESTAMP}
Backup Type: Logical (pg_dump)
PostgreSQL Version: $(PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -t -c "SELECT version();")
Databases: ${databases}
EOF

    log "Logical backup completed: ${compressed_file}"
    return 0
}

# Archive WAL files for point-in-time recovery
archive_wal_files() {
    log "Archiving WAL files for point-in-time recovery"

    # Enable WAL archiving in PostgreSQL (should be configured in postgresql.conf)
    # archive_mode = on
    # archive_command = 'rsync -a %p /backup/postgres-wal/%f'

    # Check WAL archive status
    local wal_status
    wal_status=$(PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -t -c "SELECT archived_count, failed_count FROM pg_stat_archiver;")

    log "WAL Archive Status: ${wal_status}"

    # Force WAL switch to ensure all changes are archived
    PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -c "SELECT pg_switch_wal();" > /dev/null 2>&1 || true

    # Create WAL archive manifest
    find "${WAL_ARCHIVE_DIR}" -type f -name "*.wal" -o -name "*.[0-9A-F]*" > "${WAL_ARCHIVE_DIR}/wal-manifest-${TIMESTAMP}.txt"

    log "WAL archiving completed"
}

# Create physical backup using pg_basebackup (faster restore)
perform_physical_backup() {
    local basebackup_dir="${BACKUP_DIR}/basebackup-${TIMESTAMP}"

    log "Starting physical backup: ${basebackup_dir}"

    mkdir -p "${basebackup_dir}"

    # Perform base backup
    PGPASSWORD="${PGPASSWORD}" pg_basebackup \
        -h "${PGHOST}" \
        -p "${PGPORT}" \
        -U "${PGUSER}" \
        -D "${basebackup_dir}" \
        --format=tar \
        --gzip \
        --compress=9 \
        --checkpoint=fast \
        --progress \
        --verbose \
        --wal-method=fetch \
        2>> "${LOG_FILE}"

    # Create recovery configuration
    cat > "${basebackup_dir}/recovery.conf.sample" <<EOF
restore_command = 'cp ${WAL_ARCHIVE_DIR}/%f %p'
recovery_target_time = '${TIMESTAMP}'
recovery_target_action = 'promote'
EOF

    log "Physical backup completed: ${basebackup_dir}"
    return 0
}

# Verify backup integrity
verify_backup() {
    local dump_dir=$1

    log "Verifying backup integrity"

    # Test restore to a temporary database (optional, resource-intensive)
    # For now, just verify files exist and are readable
    local backup_files
    backup_files=$(find "${dump_dir}" -name "*.dump" -o -name "*.sql.gz" 2>/dev/null | wc -l)

    if [[ ${backup_files} -eq 0 ]]; then
        log_error "No backup files found"
        return 1
    fi

    # Verify gzip integrity
    for file in "${dump_dir}"/*.gz; do
        if [[ -f "${file}" ]]; then
            if ! gzip -t "${file}" 2>/dev/null; then
                log_error "Corrupted backup file: ${file}"
                return 1
            fi
        fi
    done

    log "Backup verification completed: ${backup_files} files verified"
    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up backups older than ${DUMP_RETENTION_DAYS} days"

    # Remove old SQL dumps
    find "${BACKUP_DIR}" -name "*.sql.gz" -mtime +${DUMP_RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_DIR}" -name "*.dump" -mtime +${DUMP_RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_DIR}" -name "*.meta" -mtime +${DUMP_RETENTION_DAYS} -delete 2>/dev/null || true

    # Remove old basebackup directories (keep only last 2 for Full backups)
    if [[ "${BACKUP_LEVEL}" == "Full" ]]; then
        ls -dt "${BACKUP_DIR}"/basebackup-* 2>/dev/null | tail -n +3 | xargs rm -rf 2>/dev/null || true
    fi

    # Cleanup old WAL files (keep last 30 days)
    find "${WAL_ARCHIVE_DIR}" -name "*.wal" -mtime +30 -delete 2>/dev/null || true

    log "Cleanup completed"
}

# Calculate backup statistics
calculate_stats() {
    log "Calculating backup statistics"

    local total_size
    total_size=$(du -sh "${BACKUP_DIR}" | cut -f1)

    local dump_count
    dump_count=$(find "${BACKUP_DIR}" -name "*.dump" -o -name "*.sql.gz" | wc -l)

    local wal_count
    wal_count=$(find "${WAL_ARCHIVE_DIR}" -type f | wc -l)

    cat > "${BACKUP_DIR}/stats-${TIMESTAMP}.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "backup_level": "${BACKUP_LEVEL}",
  "total_size": "${total_size}",
  "dump_count": ${dump_count},
  "wal_count": ${wal_count},
  "pghost": "${PGHOST}",
  "pgport": ${PGPORT}
}
EOF

    log "Backup statistics: Size=${total_size}, Dumps=${dump_count}, WALs=${wal_count}"
}

# Main execution
main() {
    log "=== PostgreSQL Backup Started ==="
    log "Backup Level: ${BACKUP_LEVEL}"

    # Initialize
    initialize_directories

    # Test connection
    test_connection || {
        log_error "PostgreSQL connection failed"
        exit 1
    }

    # Perform backup based on level
    case "${BACKUP_LEVEL}" in
        Full)
            perform_logical_backup || exit 1
            perform_physical_backup || log "Warning: Physical backup failed, but logical backup succeeded"
            archive_wal_files
            ;;
        Differential|Incremental)
            # For differential/incremental, we still do logical dumps (can't do true incremental with pg_dump)
            perform_logical_backup || exit 1
            archive_wal_files
            ;;
        *)
            log_error "Unknown backup level: ${BACKUP_LEVEL}"
            exit 1
            ;;
    esac

    # Verify backup
    verify_backup "${BACKUP_DIR}" || {
        log_error "Backup verification failed"
        exit 1
    }

    # Calculate statistics
    calculate_stats

    # Cleanup old backups
    cleanup_old_backups

    log "=== PostgreSQL Backup Completed Successfully ==="
    exit 0
}

# Error handler
trap 'log_error "PostgreSQL backup failed at line $LINENO"; exit 1' ERR

# Execute main
main "$@"
