#!/bin/bash
#
# MySQL/MariaDB Backup Script
# Creates consistent database dumps with transaction handling
#
# Arguments:
#   $1 - Backup Level (Full, Differential, Incremental)
#

set -euo pipefail

# Configuration
BACKUP_DIR="/backup/mysql-dump"
LOG_FILE="/var/log/bacula/mysql-backup.log"
BACKUP_LEVEL="${1:-Full}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# MySQL connection settings
MYSQL_HOST="${MYSQL_HOST:-mysql-service.default.svc.cluster.local}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

# Backup retention
DUMP_RETENTION_DAYS=7

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Create backup directory
initialize_directories() {
    mkdir -p "${BACKUP_DIR}"
    log "Backup directory initialized: ${BACKUP_DIR}"
}

# Test MySQL connection
test_connection() {
    log "Testing MySQL connection to ${MYSQL_HOST}:${MYSQL_PORT}"

    if ! mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
        log_error "Cannot connect to MySQL server"
        return 1
    fi

    log "MySQL connection successful"
    return 0
}

# Get list of databases
get_databases() {
    mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SHOW DATABASES;" -s --skip-column-names | \
        grep -Ev '^(information_schema|performance_schema|mysql|sys)$'
}

# Perform full database backup
perform_full_backup() {
    log "Starting full MySQL backup"

    local databases
    databases=$(get_databases)

    # Backup all databases
    for db in ${databases}; do
        log "Backing up database: ${db}"

        local dump_file="${BACKUP_DIR}/mysql-${db}-${TIMESTAMP}.sql"

        mysqldump \
            -h "${MYSQL_HOST}" \
            -P "${MYSQL_PORT}" \
            -u "${MYSQL_USER}" \
            -p"${MYSQL_PASSWORD}" \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            --add-drop-database \
            --databases "${db}" \
            --result-file="${dump_file}" \
            2>> "${LOG_FILE}"

        # Compress dump
        gzip "${dump_file}"
        log "Database ${db} backed up and compressed: ${dump_file}.gz"
    done

    # Backup MySQL users and grants
    log "Backing up MySQL users and grants"
    mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" mysql -e "SELECT * FROM user;" > "${BACKUP_DIR}/mysql-users-${TIMESTAMP}.txt"
    mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SHOW GRANTS;" > "${BACKUP_DIR}/mysql-grants-${TIMESTAMP}.txt" || true

    # Create all-databases backup
    log "Creating all-databases backup"
    mysqldump \
        -h "${MYSQL_HOST}" \
        -P "${MYSQL_PORT}" \
        -u "${MYSQL_USER}" \
        -p"${MYSQL_PASSWORD}" \
        --all-databases \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --result-file="${BACKUP_DIR}/mysql-all-${TIMESTAMP}.sql" \
        2>> "${LOG_FILE}"

    gzip "${BACKUP_DIR}/mysql-all-${TIMESTAMP}.sql"

    log "Full backup completed"
}

# Create backup metadata
create_metadata() {
    local mysql_version
    mysql_version=$(mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT VERSION();" -s --skip-column-names)

    local databases
    databases=$(get_databases | tr '\n' ',' | sed 's/,$//')

    cat > "${BACKUP_DIR}/mysql-${TIMESTAMP}.meta" <<EOF
Backup Timestamp: ${TIMESTAMP}
Backup Type: ${BACKUP_LEVEL}
MySQL Version: ${mysql_version}
MySQL Host: ${MYSQL_HOST}:${MYSQL_PORT}
Databases: ${databases}
Backup Method: mysqldump with single-transaction
EOF

    log "Metadata created"
}

# Verify backup integrity
verify_backup() {
    log "Verifying backup integrity"

    local backup_files
    backup_files=$(find "${BACKUP_DIR}" -name "mysql-*-${TIMESTAMP}.sql.gz" 2>/dev/null | wc -l)

    if [[ ${backup_files} -eq 0 ]]; then
        log_error "No backup files found"
        return 1
    fi

    # Verify gzip integrity
    for file in "${BACKUP_DIR}"/mysql-*-"${TIMESTAMP}".sql.gz; do
        if [[ -f "${file}" ]]; then
            if ! gzip -t "${file}" 2>/dev/null; then
                log_error "Corrupted backup file: ${file}"
                return 1
            fi
            log "Verified: ${file}"
        fi
    done

    log "Backup verification completed: ${backup_files} files verified"
    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up backups older than ${DUMP_RETENTION_DAYS} days"

    find "${BACKUP_DIR}" -name "mysql-*.sql.gz" -mtime +${DUMP_RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_DIR}" -name "mysql-*.meta" -mtime +${DUMP_RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_DIR}" -name "mysql-*.txt" -mtime +${DUMP_RETENTION_DAYS} -delete 2>/dev/null || true

    log "Cleanup completed"
}

# Calculate statistics
calculate_stats() {
    log "Calculating backup statistics"

    local total_size
    total_size=$(du -sh "${BACKUP_DIR}" | cut -f1)

    local dump_count
    dump_count=$(find "${BACKUP_DIR}" -name "mysql-*-${TIMESTAMP}.sql.gz" | wc -l)

    cat > "${BACKUP_DIR}/stats-${TIMESTAMP}.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "backup_level": "${BACKUP_LEVEL}",
  "total_size": "${total_size}",
  "dump_count": ${dump_count},
  "mysql_host": "${MYSQL_HOST}",
  "mysql_port": ${MYSQL_PORT}
}
EOF

    log "Backup statistics: Size=${total_size}, Dumps=${dump_count}"
}

# Main execution
main() {
    log "=== MySQL Backup Started ==="
    log "Backup Level: ${BACKUP_LEVEL}"

    # Initialize
    initialize_directories

    # Test connection
    test_connection || {
        log_error "MySQL connection failed"
        exit 1
    }

    # Perform backup
    perform_full_backup || {
        log_error "Backup failed"
        exit 1
    }

    # Create metadata
    create_metadata

    # Verify backup
    verify_backup || {
        log_error "Backup verification failed"
        exit 1
    }

    # Calculate statistics
    calculate_stats

    # Cleanup
    cleanup_old_backups

    log "=== MySQL Backup Completed Successfully ==="
    exit 0
}

# Error handler
trap 'log_error "MySQL backup failed at line $LINENO"; exit 1' ERR

# Execute main
main "$@"
