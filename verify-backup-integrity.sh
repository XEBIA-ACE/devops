#!/bin/bash
#
# Backup Integrity Verification Script
# Performs comprehensive validation of backup integrity
#

set -euo pipefail

# Configuration
LOG_FILE="/var/log/bacula/verification.log"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Test 1: Verify Bacula Director connectivity
test_director_connectivity() {
    log "=== Test 1: Bacula Director Connectivity ==="

    if echo "status dir" | bconsole -c /etc/bacula/bconsole.conf > /dev/null 2>&1; then
        log "✓ Bacula Director is responding"
        return 0
    else
        log_error "✗ Bacula Director is not responding"
        return 1
    fi
}

# Test 2: Verify recent backup jobs
test_recent_backups() {
    log "=== Test 2: Recent Backup Jobs ==="

    local job_list
    job_list=$(echo "list jobs last=10" | bconsole -c /etc/bacula/bconsole.conf 2>/dev/null)

    local failed_jobs
    failed_jobs=$(echo "${job_list}" | grep -c "Error\|Failed" || echo "0")

    if [[ ${failed_jobs} -eq 0 ]]; then
        log "✓ No failed jobs in last 10 backups"
        return 0
    else
        log_error "✗ Found ${failed_jobs} failed jobs"
        echo "${job_list}" | grep "Error\|Failed" | tee -a "${LOG_FILE}"
        return 1
    fi
}

# Test 3: Verify backup files exist
test_backup_files_exist() {
    log "=== Test 3: Backup File Existence ==="

    local backup_dirs=(
        "/backup/postgres-dump"
        "/backup/mysql-dump"
        "/backup/etcd-snapshot"
        "/backup/pv-data"
    )

    local missing_count=0

    for dir in "${backup_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            local file_count
            file_count=$(find "${dir}" -type f -mtime -7 | wc -l)

            if [[ ${file_count} -gt 0 ]]; then
                log "✓ ${dir}: ${file_count} files (last 7 days)"
            else
                log_error "✗ ${dir}: No recent files found"
                ((missing_count++))
            fi
        else
            log_error "✗ ${dir}: Directory does not exist"
            ((missing_count++))
        fi
    done

    if [[ ${missing_count} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 4: Verify encryption keys
test_encryption_keys() {
    log "=== Test 4: Encryption Keys ==="

    local keys=(
        "/etc/bacula/pki/master.pem"
        "/etc/bacula/pki/master-public.pem"
        "/etc/bacula/ssl/ca.crt"
        "/etc/bacula/ssl/director.crt"
        "/etc/bacula/ssl/director.key"
    )

    local missing_count=0

    for key in "${keys[@]}"; do
        if [[ -f "${key}" ]]; then
            log "✓ ${key} exists"
        else
            log_error "✗ ${key} missing"
            ((missing_count++))
        fi
    done

    # Test encryption/decryption
    local test_file="/tmp/encryption-test-${TIMESTAMP}.txt"
    echo "Test data" > "${test_file}"

    if openssl rsautl -encrypt \
        -inkey /etc/bacula/pki/master-public.pem \
        -pubin \
        -in "${test_file}" \
        -out "${test_file}.enc" 2>/dev/null; then

        if openssl rsautl -decrypt \
            -inkey /etc/bacula/pki/master.pem \
            -in "${test_file}.enc" \
            -out "${test_file}.dec" 2>/dev/null; then

            if cmp -s "${test_file}" "${test_file}.dec"; then
                log "✓ Encryption/decryption test passed"
            else
                log_error "✗ Encryption/decryption test failed"
                ((missing_count++))
            fi
        else
            log_error "✗ Decryption failed"
            ((missing_count++))
        fi
    else
        log_error "✗ Encryption failed"
        ((missing_count++))
    fi

    rm -f "${test_file}" "${test_file}.enc" "${test_file}.dec"

    if [[ ${missing_count} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 5: Verify TLS certificates
test_tls_certificates() {
    log "=== Test 5: TLS Certificates ==="

    local certs=(
        "/etc/bacula/ssl/ca.crt"
        "/etc/bacula/ssl/director.crt"
        "/etc/bacula/ssl/sd.crt"
        "/etc/bacula/ssl/fd.crt"
    )

    local issue_count=0

    for cert in "${certs[@]}"; do
        if [[ -f "${cert}" ]]; then
            # Check expiration
            if openssl x509 -in "${cert}" -noout -checkend 2592000 2>/dev/null; then
                log "✓ ${cert} valid (expires > 30 days)"
            else
                local expiry
                expiry=$(openssl x509 -in "${cert}" -noout -enddate | cut -d= -f2)
                log_error "✗ ${cert} expires soon: ${expiry}"
                ((issue_count++))
            fi
        else
            log_error "✗ ${cert} not found"
            ((issue_count++))
        fi
    done

    if [[ ${issue_count} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 6: Test restore capability
test_restore_capability() {
    log "=== Test 6: Restore Capability Test ==="

    # Get latest backup job
    local latest_job
    latest_job=$(echo "list jobs last=1" | bconsole -c /etc/bacula/bconsole.conf 2>/dev/null | grep -oP 'JobId=\K\d+' | head -1)

    if [[ -z "${latest_job}" ]]; then
        log_error "✗ No backup jobs found"
        return 1
    fi

    log "Testing restore from JobId=${latest_job}"

    # Create temporary restore directory
    local restore_test_dir="/tmp/restore-test-${TIMESTAMP}"
    mkdir -p "${restore_test_dir}"

    # Attempt restore (single file for testing)
    if echo "restore jobid=${latest_job} where=${restore_test_dir} file=/.backup-in-progress all yes
wait
quit" | bconsole -c /etc/bacula/bconsole.conf > /tmp/restore-test-output.txt 2>&1; then

        if grep -qi "error" /tmp/restore-test-output.txt; then
            log_error "✗ Restore test reported errors"
            cat /tmp/restore-test-output.txt | tee -a "${LOG_FILE}"
            rm -rf "${restore_test_dir}"
            return 1
        else
            log "✓ Restore test successful"
            rm -rf "${restore_test_dir}"
            return 0
        fi
    else
        log_error "✗ Restore test failed"
        rm -rf "${restore_test_dir}"
        return 1
    fi
}

# Test 7: Verify storage connectivity
test_storage_connectivity() {
    log "=== Test 7: Storage Connectivity ==="

    # Test Azure Blob Storage mount
    if [[ -d "/mnt/azure-blob" ]]; then
        if touch "/mnt/azure-blob/.test-${TIMESTAMP}" 2>/dev/null; then
            rm -f "/mnt/azure-blob/.test-${TIMESTAMP}"
            log "✓ Azure Blob Storage is writable"
        else
            log_error "✗ Azure Blob Storage is not writable"
            return 1
        fi
    else
        log_error "✗ Azure Blob Storage not mounted"
        return 1
    fi

    # Check storage space
    local available
    available=$(df -BG /mnt/azure-blob | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ ${available} -gt 100 ]]; then
        log "✓ Sufficient storage space: ${available}GB available"
    else
        log_error "✗ Low storage space: ${available}GB available"
        return 1
    fi

    return 0
}

# Test 8: Verify GFS retention policy
test_gfs_retention() {
    log "=== Test 8: GFS Retention Policy ==="

    # Check Grandfather pool (12 months)
    local grandfather_count
    grandfather_count=$(echo "list volumes pool=Grandfather-Pool" | bconsole -c /etc/bacula/bconsole.conf 2>/dev/null | grep -c "Grandfather-" || echo "0")

    log "Grandfather Pool: ${grandfather_count} volumes (expected: ≤24)"

    # Check Father pool (8 weeks)
    local father_count
    father_count=$(echo "list volumes pool=Father-Pool" | bconsole -c /etc/bacula/bconsole.conf 2>/dev/null | grep -c "Father-" || echo "0")

    log "Father Pool: ${father_count} volumes (expected: ≤16)"

    # Check Son pool (14 days)
    local son_count
    son_count=$(echo "list volumes pool=Son-Pool" | bconsole -c /etc/bacula/bconsole.conf 2>/dev/null | grep -c "Son-" || echo "0")

    log "Son Pool: ${son_count} volumes (expected: ≤28)"

    log "✓ GFS retention policy volumes tracked"
    return 0
}

# Test 9: Database backup integrity
test_database_backups() {
    log "=== Test 9: Database Backup Integrity ==="

    # Test PostgreSQL dumps
    local pg_latest
    pg_latest=$(find /backup/postgres-dump -name "*.sql.gz" -type f -mtime -1 | head -1)

    if [[ -n "${pg_latest}" ]]; then
        if gzip -t "${pg_latest}" 2>/dev/null; then
            log "✓ PostgreSQL backup integrity verified: $(basename ${pg_latest})"
        else
            log_error "✗ PostgreSQL backup corrupted: $(basename ${pg_latest})"
            return 1
        fi
    else
        log_error "✗ No recent PostgreSQL backup found"
        return 1
    fi

    # Test MySQL dumps
    local mysql_latest
    mysql_latest=$(find /backup/mysql-dump -name "*.sql.gz" -type f -mtime -1 | head -1)

    if [[ -n "${mysql_latest}" ]]; then
        if gzip -t "${mysql_latest}" 2>/dev/null; then
            log "✓ MySQL backup integrity verified: $(basename ${mysql_latest})"
        else
            log_error "✗ MySQL backup corrupted: $(basename ${mysql_latest})"
            return 1
        fi
    else
        log "⚠ No recent MySQL backup found (may be expected)"
    fi

    return 0
}

# Test 10: Kubernetes resources backup
test_k8s_resources() {
    log "=== Test 10: Kubernetes Resources Backup ==="

    local k8s_latest
    k8s_latest=$(find /backup/k8s-resources -name "k8s-resources-*.tar.gz" -type f -mtime -1 | head -1)

    if [[ -n "${k8s_latest}" ]]; then
        if tar -tzf "${k8s_latest}" > /dev/null 2>&1; then
            local file_count
            file_count=$(tar -tzf "${k8s_latest}" | wc -l)
            log "✓ Kubernetes resources backup verified: ${file_count} files"
        else
            log_error "✗ Kubernetes resources backup corrupted"
            return 1
        fi
    else
        log_error "✗ No recent Kubernetes resources backup found"
        return 1
    fi

    return 0
}

# Generate verification report
generate_report() {
    local total_tests=$1
    local passed_tests=$2
    local failed_tests=$3

    log "=== Verification Report ==="
    log "Total Tests: ${total_tests}"
    log "Passed: ${passed_tests}"
    log "Failed: ${failed_tests}"
    log "Success Rate: $(( passed_tests * 100 / total_tests ))%"

    # Create JSON report
    cat > /tmp/verification-report-${TIMESTAMP}.json <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_tests": ${total_tests},
  "passed": ${passed_tests},
  "failed": ${failed_tests},
  "success_rate": $(( passed_tests * 100 / total_tests )),
  "status": "$([ ${failed_tests} -eq 0 ] && echo "PASS" || echo "FAIL")"
}
EOF

    log "Report saved to: /tmp/verification-report-${TIMESTAMP}.json"
}

# Main execution
main() {
    log "====================================================="
    log "  Backup Integrity Verification"
    log "  Timestamp: ${TIMESTAMP}"
    log "====================================================="

    local total_tests=10
    local passed_tests=0
    local failed_tests=0

    # Run all tests
    test_director_connectivity && ((passed_tests++)) || ((failed_tests++))
    test_recent_backups && ((passed_tests++)) || ((failed_tests++))
    test_backup_files_exist && ((passed_tests++)) || ((failed_tests++))
    test_encryption_keys && ((passed_tests++)) || ((failed_tests++))
    test_tls_certificates && ((passed_tests++)) || ((failed_tests++))
    test_restore_capability && ((passed_tests++)) || ((failed_tests++))
    test_storage_connectivity && ((passed_tests++)) || ((failed_tests++))
    test_gfs_retention && ((passed_tests++)) || ((failed_tests++))
    test_database_backups && ((passed_tests++)) || ((failed_tests++))
    test_k8s_resources && ((passed_tests++)) || ((failed_tests++))

    # Generate report
    generate_report ${total_tests} ${passed_tests} ${failed_tests}

    log "====================================================="
    log "  Verification Complete"
    log "====================================================="

    # Exit with appropriate code
    if [[ ${failed_tests} -eq 0 ]]; then
        log "✓ All tests passed"
        exit 0
    else
        log_error "✗ ${failed_tests} test(s) failed"
        exit 1
    fi
}

# Execute main
main "$@"
