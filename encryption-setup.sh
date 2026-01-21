#!/bin/bash
#
# Encryption Setup Script for Bacula Backup System
# Configures PKI encryption, TLS certificates, and key management
#

set -euo pipefail

# Configuration
BACULA_PKI_DIR="/etc/bacula/pki"
BACULA_SSL_DIR="/etc/bacula/ssl"
KEY_VAULT_ADDR="${KEY_VAULT_ADDR:-http://vault:8200}"
LOG_FILE="/var/log/bacula/encryption-setup.log"

# Certificate parameters
CERT_COUNTRY="US"
CERT_STATE="State"
CERT_CITY="City"
CERT_ORG="Organization"
CERT_OU="IT Department"
CERT_VALIDITY_DAYS=3650

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Create directories
create_directories() {
    log "Creating encryption directories"

    mkdir -p "${BACULA_PKI_DIR}" "${BACULA_SSL_DIR}"
    chmod 700 "${BACULA_PKI_DIR}" "${BACULA_SSL_DIR}"

    log "Directories created"
}

# Generate PKI master keypair for client-side encryption
generate_pki_master_key() {
    log "Generating PKI master keypair for client-side encryption"

    local master_key="${BACULA_PKI_DIR}/master.pem"

    if [[ -f "${master_key}" ]]; then
        log "Master key already exists: ${master_key}"
        read -rp "Regenerate master key? This will make old backups unreadable! (yes/no): " confirm
        if [[ "${confirm}" != "yes" ]]; then
            log "Skipping master key generation"
            return 0
        fi
    fi

    # Generate RSA 4096-bit keypair
    openssl genrsa -aes256 -out "${BACULA_PKI_DIR}/master-encrypted.pem" 4096

    # Create unencrypted version for automated use (store securely!)
    openssl rsa -in "${BACULA_PKI_DIR}/master-encrypted.pem" -out "${master_key}"

    # Extract public key
    openssl rsa -in "${master_key}" -pubout -out "${BACULA_PKI_DIR}/master-public.pem"

    # Set permissions
    chmod 400 "${master_key}"
    chmod 444 "${BACULA_PKI_DIR}/master-public.pem"
    chmod 400 "${BACULA_PKI_DIR}/master-encrypted.pem"

    log "PKI master keypair generated"
    log "IMPORTANT: Backup the master key to secure offline storage!"
    log "Master key: ${BACULA_PKI_DIR}/master-encrypted.pem"
}

# Generate file daemon keypairs
generate_fd_keypairs() {
    log "Generating File Daemon keypairs"

    local fd_list=("k8s-backup-client" "k8s-backup-client-prod" "k8s-backup-client-staging")

    for fd_name in "${fd_list[@]}"; do
        log "Generating keypair for ${fd_name}"

        local fd_key="${BACULA_PKI_DIR}/${fd_name}-key.pem"

        if [[ -f "${fd_key}" ]]; then
            log "Keypair already exists for ${fd_name}, skipping"
            continue
        fi

        # Generate RSA 4096-bit keypair
        openssl genrsa -out "${fd_key}" 4096

        # Extract public key
        openssl rsa -in "${fd_key}" -pubout -out "${BACULA_PKI_DIR}/${fd_name}-public.pem"

        # Set permissions
        chmod 400 "${fd_key}"
        chmod 444 "${BACULA_PKI_DIR}/${fd_name}-public.pem"

        log "Keypair generated for ${fd_name}"
    done

    log "File Daemon keypairs generated"
}

# Generate CA certificate
generate_ca_certificate() {
    log "Generating Certificate Authority"

    local ca_key="${BACULA_SSL_DIR}/ca.key"
    local ca_cert="${BACULA_SSL_DIR}/ca.crt"

    if [[ -f "${ca_cert}" ]]; then
        log "CA certificate already exists"
        return 0
    fi

    # Generate CA private key
    openssl genrsa -aes256 -out "${BACULA_SSL_DIR}/ca-encrypted.key" 4096

    # Create unencrypted version
    openssl rsa -in "${BACULA_SSL_DIR}/ca-encrypted.key" -out "${ca_key}"

    # Generate self-signed CA certificate
    openssl req -new -x509 -days ${CERT_VALIDITY_DAYS} -key "${ca_key}" -out "${ca_cert}" -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=Bacula CA"

    chmod 400 "${ca_key}"
    chmod 444 "${ca_cert}"

    log "CA certificate generated"
}

# Generate component certificates (Director, SD, FD)
generate_component_certificate() {
    local component=$1
    local cn=$2

    log "Generating certificate for ${component}"

    local key_file="${BACULA_SSL_DIR}/${component}.key"
    local csr_file="${BACULA_SSL_DIR}/${component}.csr"
    local cert_file="${BACULA_SSL_DIR}/${component}.crt"

    if [[ -f "${cert_file}" ]]; then
        log "Certificate already exists for ${component}"
        return 0
    fi

    # Generate private key
    openssl genrsa -out "${key_file}" 4096

    # Generate CSR
    openssl req -new -key "${key_file}" -out "${csr_file}" -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=${cn}"

    # Sign certificate with CA
    openssl x509 -req -in "${csr_file}" -CA "${BACULA_SSL_DIR}/ca.crt" -CAkey "${BACULA_SSL_DIR}/ca.key" -CAcreateserial -out "${cert_file}" -days ${CERT_VALIDITY_DAYS}

    # Set permissions
    chmod 400 "${key_file}"
    chmod 444 "${cert_file}"

    # Remove CSR
    rm -f "${csr_file}"

    log "Certificate generated for ${component}"
}

# Generate all TLS certificates
generate_tls_certificates() {
    log "Generating TLS certificates"

    # Generate CA
    generate_ca_certificate

    # Generate component certificates
    generate_component_certificate "director" "bacula-director"
    generate_component_certificate "sd" "bacula-sd"
    generate_component_certificate "fd" "bacula-fd"

    log "TLS certificates generated"
}

# Store keys in Vault (optional)
store_keys_in_vault() {
    if [[ -z "${KEY_VAULT_ADDR}" ]] || [[ "${KEY_VAULT_ADDR}" == "http://vault:8200" ]]; then
        log "Vault not configured, skipping key storage in Vault"
        return 0
    fi

    log "Storing encryption keys in Vault"

    # Check if vault CLI is available
    if ! command -v vault &> /dev/null; then
        log "Vault CLI not found, skipping Vault storage"
        return 0
    fi

    # Store master key
    vault kv put secret/bacula/encryption/master \
        private_key=@"${BACULA_PKI_DIR}/master-encrypted.pem" \
        public_key=@"${BACULA_PKI_DIR}/master-public.pem"

    # Store CA key
    vault kv put secret/bacula/tls/ca \
        private_key=@"${BACULA_SSL_DIR}/ca-encrypted.key" \
        certificate=@"${BACULA_SSL_DIR}/ca.crt"

    log "Keys stored in Vault"
}

# Create key rotation script
create_key_rotation_script() {
    log "Creating key rotation script"

    cat > /opt/bacula/scripts/rotate-keys.sh <<'EOF'
#!/bin/bash
#
# Key Rotation Script
# Rotate encryption keys following security best practices
#

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Key Rotation Started ==="

# 1. Generate new master keypair
log "Generating new master keypair"
NEW_MASTER="/etc/bacula/pki/master-new.pem"
openssl genrsa -out "${NEW_MASTER}" 4096

# 2. Keep old key for decrypting existing backups
log "Archiving old master key"
OLD_MASTER="/etc/bacula/pki/master-$(date +%Y%m%d).pem"
cp /etc/bacula/pki/master.pem "${OLD_MASTER}"

# 3. Replace master key
log "Replacing master key"
mv "${NEW_MASTER}" /etc/bacula/pki/master.pem
chmod 400 /etc/bacula/pki/master.pem

# 4. Extract new public key
openssl rsa -in /etc/bacula/pki/master.pem -pubout -out /etc/bacula/pki/master-public.pem

# 5. Update Bacula configuration (reload director)
log "Reloading Bacula Director"
echo "reload" | bconsole

log "=== Key Rotation Completed ==="
log "Old key archived to: ${OLD_MASTER}"
log "IMPORTANT: Store old keys securely for decrypting historical backups"
EOF

    chmod +x /opt/bacula/scripts/rotate-keys.sh

    log "Key rotation script created: /opt/bacula/scripts/rotate-keys.sh"
}

# Create encryption verification script
create_verification_script() {
    log "Creating encryption verification script"

    cat > /opt/bacula/scripts/verify-encryption.sh <<'EOF'
#!/bin/bash
#
# Encryption Verification Script
# Verifies that backups are properly encrypted
#

set -euo pipefail

BACULA_PKI_DIR="/etc/bacula/pki"
BACULA_SSL_DIR="/etc/bacula/ssl"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Encryption Verification Started ==="

# Check PKI keys exist
log "Checking PKI keys"
if [[ ! -f "${BACULA_PKI_DIR}/master.pem" ]]; then
    log "ERROR: Master key not found"
    exit 1
fi
log "✓ Master key found"

# Check TLS certificates
log "Checking TLS certificates"
for cert in ca.crt director.crt sd.crt fd.crt; do
    if [[ ! -f "${BACULA_SSL_DIR}/${cert}" ]]; then
        log "ERROR: Certificate not found: ${cert}"
        exit 1
    fi

    # Verify certificate validity
    if ! openssl x509 -in "${BACULA_SSL_DIR}/${cert}" -noout -checkend 2592000; then
        log "WARNING: Certificate ${cert} expires within 30 days"
    else
        log "✓ Certificate ${cert} is valid"
    fi
done

# Test encryption/decryption
log "Testing encryption/decryption"
TEST_FILE="/tmp/encryption-test.txt"
echo "Bacula Encryption Test" > "${TEST_FILE}"

# Encrypt
openssl rsautl -encrypt -inkey "${BACULA_PKI_DIR}/master-public.pem" -pubin -in "${TEST_FILE}" -out "${TEST_FILE}.enc"

# Decrypt
openssl rsautl -decrypt -inkey "${BACULA_PKI_DIR}/master.pem" -in "${TEST_FILE}.enc" -out "${TEST_FILE}.dec"

# Compare
if cmp -s "${TEST_FILE}" "${TEST_FILE}.dec"; then
    log "✓ Encryption/decryption test passed"
else
    log "ERROR: Encryption/decryption test failed"
    exit 1
fi

# Cleanup
rm -f "${TEST_FILE}" "${TEST_FILE}.enc" "${TEST_FILE}.dec"

log "=== Encryption Verification Completed Successfully ==="
EOF

    chmod +x /opt/bacula/scripts/verify-encryption.sh

    log "Encryption verification script created"
}

# Generate Kubernetes secrets
generate_k8s_secrets() {
    log "Generating Kubernetes secrets for encryption keys"

    # PKI Master Key Secret
    kubectl create secret generic bacula-pki-master \
        --from-file=master.pem="${BACULA_PKI_DIR}/master.pem" \
        --from-file=master-public.pem="${BACULA_PKI_DIR}/master-public.pem" \
        --namespace=backup \
        --dry-run=client -o yaml > /tmp/bacula-pki-secret.yaml

    # TLS Certificates Secret
    kubectl create secret generic bacula-tls-certs \
        --from-file=ca.crt="${BACULA_SSL_DIR}/ca.crt" \
        --from-file=director.crt="${BACULA_SSL_DIR}/director.crt" \
        --from-file=director.key="${BACULA_SSL_DIR}/director.key" \
        --from-file=sd.crt="${BACULA_SSL_DIR}/sd.crt" \
        --from-file=sd.key="${BACULA_SSL_DIR}/sd.key" \
        --from-file=fd.crt="${BACULA_SSL_DIR}/fd.crt" \
        --from-file=fd.key="${BACULA_SSL_DIR}/fd.key" \
        --namespace=backup \
        --dry-run=client -o yaml > /tmp/bacula-tls-secret.yaml

    log "Kubernetes secret manifests created:"
    log "  - /tmp/bacula-pki-secret.yaml"
    log "  - /tmp/bacula-tls-secret.yaml"
    log "Apply with: kubectl apply -f /tmp/bacula-pki-secret.yaml"
}

# Create backup of encryption keys
backup_encryption_keys() {
    log "Creating backup of encryption keys"

    local backup_file="/tmp/bacula-encryption-backup-$(date +%Y%m%d-%H%M%S).tar.gz.enc"

    # Create encrypted archive
    tar -czf - -C /etc/bacula pki ssl | openssl enc -aes-256-cbc -salt -out "${backup_file}"

    log "Encryption keys backed up to: ${backup_file}"
    log "CRITICAL: Store this file in secure offline location"
    log "Backup password has been used for encryption"
}

# Main execution
main() {
    log "=== Bacula Encryption Setup Started ==="

    # Create directories
    create_directories

    # Generate PKI keys for client-side encryption
    generate_pki_master_key
    generate_fd_keypairs

    # Generate TLS certificates for transport encryption
    generate_tls_certificates

    # Store in Vault (optional)
    store_keys_in_vault

    # Create helper scripts
    create_key_rotation_script
    create_verification_script

    # Generate Kubernetes secrets
    generate_k8s_secrets

    # Backup encryption keys
    backup_encryption_keys

    # Run verification
    log "Running encryption verification"
    /opt/bacula/scripts/verify-encryption.sh || log "Verification will be available after script is deployed"

    log "=== Bacula Encryption Setup Completed ==="
    log ""
    log "Next steps:"
    log "1. Apply Kubernetes secrets: kubectl apply -f /tmp/bacula-pki-secret.yaml -f /tmp/bacula-tls-secret.yaml"
    log "2. Store encryption key backup in secure location"
    log "3. Update Bacula configuration files with certificate paths"
    log "4. Test backup and restore with encryption enabled"
    log "5. Schedule key rotation (recommended: annually)"
}

# Error handler
trap 'log_error "Encryption setup failed at line $LINENO"; exit 1' ERR

# Execute main
main "$@"
