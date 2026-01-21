#!/bin/bash
#
# Database Restore Script (PostgreSQL/MySQL)
# Supports point-in-time recovery and full restoration
#
# Usage: restore-database.sh [OPTIONS]
#   -t TYPE        : Database type (postgres|mysql)
#   -f DUMP_FILE   : Dump file to restore
#   -d DB_NAME     : Target database name
#   -p PITR_TIME   : Point-in-time recovery timestamp (PostgreSQL only)
#   -h HOST        : Database host
#   -u USER        : Database user
#   -n NAMESPACE   : Kubernetes namespace
#

set -euo pipefail

# Configuration
LOG_FILE="/var/log/bacula/restore-database.log"
BACKUP_DIR="/backup"

# Default values
DB_TYPE=""
DUMP_FILE=""
DB_NAME=""
PITR_TIME=""
DB_HOST=""
DB_USER=""
NAMESPACE="default"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Parse arguments
parse_args() {
    while getopts "t:f:d:p:h:u:n:" opt; do
        case ${opt} in
            t) DB_TYPE="${OPTARG}" ;;
            f) DUMP_FILE="${OPTARG}" ;;
            d) DB_NAME="${OPTARG}" ;;
            p) PITR_TIME="${OPTARG}" ;;
            h) DB_HOST="${OPTARG}" ;;
            u) DB_USER="${OPTARG}" ;;
            n) NAMESPACE="${OPTARG}" ;;
            *)
                log_error "Invalid option"
                exit 1
                ;;
        esac
    done
}

# Validate arguments
validate_args() {
    if [[ -z "${DB_TYPE}" ]]; then
        log_error "Database type not specified (-t)"
        exit 1
    fi

    if [[ "${DB_TYPE}" != "postgres" ]] && [[ "${DB_TYPE}" != "mysql" ]]; then
        log_error "Invalid database type: ${DB_TYPE}. Must be 'postgres' or 'mysql'"
        exit 1
    fi

    log "Database type: ${DB_TYPE}"
}

# List available backups
list_available_backups() {
    local db_type=$1

    log "Listing available backups for ${db_type}"

    case "${db_type}" in
        postgres)
            log "PostgreSQL backups:"
            find "${BACKUP_DIR}/postgres-dump" -name "*.sql.gz" -o -name "*.dump" 2>/dev/null | sort -r | head -20
            ;;
        mysql)
            log "MySQL backups:"
            find "${BACKUP_DIR}/mysql-dump" -name "*.sql.gz" 2>/dev/null | sort -r | head -20
            ;;
    esac
}

# Select backup file interactively
select_backup_file() {
    if [[ -z "${DUMP_FILE}" ]]; then
        list_available_backups "${DB_TYPE}"

        echo ""
        read -rp "Enter full path to dump file: " DUMP_FILE
    fi

    if [[ ! -f "${DUMP_FILE}" ]]; then
        log_error "Dump file not found: ${DUMP_FILE}"
        return 1
    fi

    log "Selected dump file: ${DUMP_FILE}"
    return 0
}

# Restore PostgreSQL database
restore_postgres() {
    local dump_file=$1
    local db_name=$2
    local db_host=${3:-postgres-service.default.svc.cluster.local}
    local db_user=${4:-postgres}

    log "=== PostgreSQL Restore Started ==="
    log "Dump File: ${dump_file}"
    log "Database: ${db_name}"
    log "Host: ${db_host}"

    # Determine dump format
    local dump_format="plain"
    if [[ "${dump_file}" == *.dump ]]; then
        dump_format="custom"
    fi

    # Create database if it doesn't exist
    log "Creating database ${db_name} if not exists"
    PGPASSWORD="${PGPASSWORD}" psql -h "${db_host}" -U "${db_user}" -d postgres -c "CREATE DATABASE ${db_name};" 2>/dev/null || log "Database already exists"

    # Restore based on format
    if [[ "${dump_format}" == "custom" ]]; then
        log "Restoring custom format dump"

        PGPASSWORD="${PGPASSWORD}" pg_restore \
            -h "${db_host}" \
            -U "${db_user}" \
            -d "${db_name}" \
            --clean \
            --if-exists \
            --verbose \
            "${dump_file}" \
            2>&1 | tee -a "${LOG_FILE}"

    else
        log "Restoring plain SQL dump"

        if [[ "${dump_file}" == *.gz ]]; then
            gunzip -c "${dump_file}" | PGPASSWORD="${PGPASSWORD}" psql -h "${db_host}" -U "${db_user}" -d "${db_name}" 2>&1 | tee -a "${LOG_FILE}"
        else
            PGPASSWORD="${PGPASSWORD}" psql -h "${db_host}" -U "${db_user}" -d "${db_name}" -f "${dump_file}" 2>&1 | tee -a "${LOG_FILE}"
        fi
    fi

    # Verify restore
    log "Verifying restore"
    local table_count
    table_count=$(PGPASSWORD="${PGPASSWORD}" psql -h "${db_host}" -U "${db_user}" -d "${db_name}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")

    log "Restored database has ${table_count} tables"

    log "=== PostgreSQL Restore Completed ==="
}

# Restore PostgreSQL with Point-in-Time Recovery
restore_postgres_pitr() {
    local target_time=$1
    local db_host=${2:-postgres-service.default.svc.cluster.local}

    log "=== PostgreSQL Point-in-Time Recovery Started ==="
    log "Target Time: ${target_time}"

    # Find the appropriate base backup
    local base_backup
    base_backup=$(find "${BACKUP_DIR}/postgres-dump" -name "basebackup-*.tar.gz" -type f 2>/dev/null | sort -r | head -1)

    if [[ -z "${base_backup}" ]]; then
        log_error "No base backup found for PITR"
        return 1
    fi

    log "Using base backup: ${base_backup}"

    # Extract base backup
    local restore_dir="/tmp/postgres-pitr-restore"
    mkdir -p "${restore_dir}"

    log "Extracting base backup"
    tar -xzf "${base_backup}" -C "${restore_dir}"

    # Create recovery.conf
    cat > "${restore_dir}/recovery.conf" <<EOF
restore_command = 'cp ${BACKUP_DIR}/postgres-wal/%f %p'
recovery_target_time = '${target_time}'
recovery_target_action = 'promote'
EOF

    log "Recovery configuration created"
    log "To complete PITR:"
    log "1. Stop PostgreSQL service"
    log "2. Replace data directory with: ${restore_dir}"
    log "3. Ensure recovery.conf is in place"
    log "4. Start PostgreSQL service"
    log "5. PostgreSQL will replay WAL logs until ${target_time}"

    log "=== PostgreSQL Point-in-Time Recovery Prepared ==="
}

# Restore MySQL database
restore_mysql() {
    local dump_file=$1
    local db_name=$2
    local db_host=${3:-mysql-service.default.svc.cluster.local}
    local db_user=${4:-root}

    log "=== MySQL Restore Started ==="
    log "Dump File: ${dump_file}"
    log "Database: ${db_name}"
    log "Host: ${db_host}"

    # Create database if it doesn't exist
    log "Creating database ${db_name} if not exists"
    mysql -h "${db_host}" -u "${db_user}" -p"${MYSQL_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${db_name};" 2>/dev/null

    # Restore dump
    if [[ "${dump_file}" == *.gz ]]; then
        log "Restoring compressed SQL dump"
        gunzip -c "${dump_file}" | mysql -h "${db_host}" -u "${db_user}" -p"${MYSQL_PASSWORD}" "${db_name}" 2>&1 | tee -a "${LOG_FILE}"
    else
        log "Restoring SQL dump"
        mysql -h "${db_host}" -u "${db_user}" -p"${MYSQL_PASSWORD}" "${db_name}" < "${dump_file}" 2>&1 | tee -a "${LOG_FILE}"
    fi

    # Verify restore
    log "Verifying restore"
    local table_count
    table_count=$(mysql -h "${db_host}" -u "${db_user}" -p"${MYSQL_PASSWORD}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${db_name}';")

    log "Restored database has ${table_count} tables"

    log "=== MySQL Restore Completed ==="
}

# Verify database connectivity
verify_database_connection() {
    local db_type=$1
    local db_host=$2
    local db_user=$3

    log "Verifying database connection"

    case "${db_type}" in
        postgres)
            if ! PGPASSWORD="${PGPASSWORD}" psql -h "${db_host}" -U "${db_user}" -d postgres -c "SELECT 1;" &> /dev/null; then
                log_error "Cannot connect to PostgreSQL"
                return 1
            fi
            ;;
        mysql)
            if ! mysql -h "${db_host}" -u "${db_user}" -p"${MYSQL_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
                log_error "Cannot connect to MySQL"
                return 1
            fi
            ;;
    esac

    log "Database connection successful"
    return 0
}

# Generate restore report
generate_restore_report() {
    local db_type=$1
    local dump_file=$2
    local db_name=$3

    local report_file="/tmp/database-restore-report-$(date +%Y%m%d-%H%M%S).txt"

    cat > "${report_file}" <<EOF
===========================================
Database Restore Report
===========================================

Restore Date: $(date)
Database Type: ${db_type}
Database Name: ${db_name}

Source:
  - Dump File: ${dump_file}
  - File Size: $(du -h "${dump_file}" 2>/dev/null | cut -f1)

Destination:
  - Host: ${DB_HOST}
  - User: ${DB_USER}
  - Namespace: ${NAMESPACE}

Status: SUCCESS

Next Steps:
  1. Verify application connectivity
  2. Check data integrity
  3. Run application tests
  4. Monitor database performance
  5. Update application configuration if needed

===========================================
EOF

    cat "${report_file}" | tee -a "${LOG_FILE}"

    log "Restore report saved to: ${report_file}"
}

# Main execution
main() {
    log "=== Database Restore Started ==="

    # Parse arguments
    parse_args "$@"

    # Validate arguments
    validate_args

    # Select backup file
    select_backup_file || exit 1

    # Set defaults for connection parameters
    [[ -z "${DB_HOST}" ]] && DB_HOST="${DB_TYPE}-service.${NAMESPACE}.svc.cluster.local"
    [[ -z "${DB_USER}" ]] && DB_USER="postgres"
    [[ "${DB_TYPE}" == "mysql" ]] && [[ -z "${DB_USER}" ]] && DB_USER="root"

    # Verify database connection
    verify_database_connection "${DB_TYPE}" "${DB_HOST}" "${DB_USER}" || {
        log_error "Database connection failed"
        exit 1
    }

    # Perform restore based on database type
    case "${DB_TYPE}" in
        postgres)
            if [[ -n "${PITR_TIME}" ]]; then
                restore_postgres_pitr "${PITR_TIME}" "${DB_HOST}"
            else
                [[ -z "${DB_NAME}" ]] && DB_NAME="restored_db"
                restore_postgres "${DUMP_FILE}" "${DB_NAME}" "${DB_HOST}" "${DB_USER}"
            fi
            ;;
        mysql)
            [[ -z "${DB_NAME}" ]] && DB_NAME="restored_db"
            restore_mysql "${DUMP_FILE}" "${DB_NAME}" "${DB_HOST}" "${DB_USER}"
            ;;
    esac

    # Generate report
    generate_restore_report "${DB_TYPE}" "${DUMP_FILE}" "${DB_NAME}"

    log "=== Database Restore Completed Successfully ==="

    exit 0
}

# Error handler
trap 'log_error "Database restore failed at line $LINENO"; exit 1' ERR

# Execute main
main "$@"
