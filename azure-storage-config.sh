#!/bin/bash
#
# Azure Blob Storage Configuration for Bacula
# Configures Azure storage with lifecycle policies and encryption
#

set -euo pipefail

# Configuration
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
AZURE_CONTAINER_NAME="${AZURE_CONTAINER_NAME:-bacula-backups}"
AZURE_REGION="${AZURE_REGION:-eastus}"
LOG_FILE="/var/log/bacula/azure-config.log"

# Lifecycle policy retention (days)
HOT_TO_COOL_DAYS=30
COOL_TO_ARCHIVE_DAYS=90
DELETE_AFTER_DAYS=365

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Check Azure CLI
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
        return 1
    fi

    log "Azure CLI found"
    return 0
}

# Login to Azure
azure_login() {
    log "Checking Azure login status"

    if ! az account show &> /dev/null; then
        log "Not logged in to Azure. Initiating login..."
        az login
    else
        log "Already logged in to Azure"
    fi

    # Show current subscription
    local subscription
    subscription=$(az account show --query name -o tsv)
    log "Using subscription: ${subscription}"
}

# Create storage account
create_storage_account() {
    log "Creating Azure Storage Account: ${AZURE_STORAGE_ACCOUNT}"

    # Check if storage account exists
    if az storage account show --name "${AZURE_STORAGE_ACCOUNT}" --resource-group "${AZURE_RESOURCE_GROUP}" &> /dev/null; then
        log "Storage account already exists"
        return 0
    fi

    # Create storage account with encryption
    az storage account create \
        --name "${AZURE_STORAGE_ACCOUNT}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --location "${AZURE_REGION}" \
        --sku Standard_GRS \
        --kind StorageV2 \
        --encryption-services blob \
        --encryption-key-source Microsoft.Storage \
        --min-tls-version TLS1_3 \
        --allow-blob-public-access false \
        --https-only true \
        --tags Purpose=Backup System=Bacula

    log "Storage account created successfully"
}

# Enable blob versioning
enable_blob_versioning() {
    log "Enabling blob versioning"

    az storage account blob-service-properties update \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --enable-versioning true \
        --enable-change-feed true

    log "Blob versioning enabled"
}

# Create container
create_container() {
    log "Creating container: ${AZURE_CONTAINER_NAME}"

    # Get storage account key
    local storage_key
    storage_key=$(az storage account keys list --account-name "${AZURE_STORAGE_ACCOUNT}" --resource-group "${AZURE_RESOURCE_GROUP}" --query '[0].value' -o tsv)

    # Create container
    az storage container create \
        --name "${AZURE_CONTAINER_NAME}" \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --public-access off

    log "Container created successfully"
}

# Configure lifecycle management policy
configure_lifecycle_policy() {
    log "Configuring lifecycle management policy"

    # Create policy JSON
    cat > /tmp/azure-lifecycle-policy.json <<EOF
{
  "rules": [
    {
      "enabled": true,
      "name": "move-to-cool-tier",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": ${HOT_TO_COOL_DAYS}
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["${AZURE_CONTAINER_NAME}/"]
        }
      }
    },
    {
      "enabled": true,
      "name": "move-to-archive-tier",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToArchive": {
              "daysAfterModificationGreaterThan": ${COOL_TO_ARCHIVE_DAYS}
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["${AZURE_CONTAINER_NAME}/Grandfather-", "${AZURE_CONTAINER_NAME}/Offsite-"]
        }
      }
    },
    {
      "enabled": true,
      "name": "delete-old-incremental",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "delete": {
              "daysAfterModificationGreaterThan": 14
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["${AZURE_CONTAINER_NAME}/Inc-"]
        }
      }
    },
    {
      "enabled": true,
      "name": "delete-after-retention",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "delete": {
              "daysAfterModificationGreaterThan": ${DELETE_AFTER_DAYS}
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"]
        }
      }
    }
  ]
}
EOF

    # Apply lifecycle policy
    az storage account management-policy create \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --policy @/tmp/azure-lifecycle-policy.json

    log "Lifecycle policy configured"
}

# Enable soft delete
enable_soft_delete() {
    log "Enabling soft delete for blobs"

    az storage account blob-service-properties update \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --enable-delete-retention true \
        --delete-retention-days 30

    log "Soft delete enabled (30 days retention)"
}

# Configure encryption at rest
configure_encryption() {
    log "Configuring encryption at rest"

    # Enable infrastructure encryption
    az storage account update \
        --name "${AZURE_STORAGE_ACCOUNT}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --encryption-key-source Microsoft.Storage

    log "Encryption configured (Microsoft-managed keys)"
    log "For customer-managed keys, configure Azure Key Vault integration"
}

# Create SAS token for Bacula
create_sas_token() {
    log "Creating SAS token for Bacula"

    local expiry_date
    expiry_date=$(date -u -d "+1 year" '+%Y-%m-%dT%H:%M:%SZ')

    local sas_token
    sas_token=$(az storage container generate-sas \
        --name "${AZURE_CONTAINER_NAME}" \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --permissions racwdl \
        --expiry "${expiry_date}" \
        -o tsv)

    log "SAS token created (expires: ${expiry_date})"
    log "SAS Token: ${sas_token}"
    log "IMPORTANT: Store this token securely and update Bacula configuration"

    # Save to file
    echo "${sas_token}" > /tmp/azure-sas-token.txt
    chmod 600 /tmp/azure-sas-token.txt
}

# Configure monitoring and alerts
configure_monitoring() {
    log "Configuring monitoring and alerts"

    # Enable storage analytics
    local storage_key
    storage_key=$(az storage account keys list --account-name "${AZURE_STORAGE_ACCOUNT}" --resource-group "${AZURE_RESOURCE_GROUP}" --query '[0].value' -o tsv)

    az storage logging update \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --log rwd \
        --retention 90 \
        --services b

    # Enable metrics
    az storage metrics update \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --hour true \
        --minute false \
        --retention 90 \
        --services b \
        --api true

    log "Monitoring configured"
}

# Create mount script for blobfuse
create_mount_script() {
    log "Creating blobfuse mount script"

    cat > /opt/bacula/scripts/mount-azure-blob.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

MOUNT_POINT="/mnt/azure-blob"
CACHE_DIR="/mnt/blobfuse-cache"

mkdir -p "${MOUNT_POINT}" "${CACHE_DIR}"

blobfuse "${MOUNT_POINT}" \
    --tmp-path="${CACHE_DIR}" \
    --container-name="${AZURE_CONTAINER_NAME}" \
    --use-https=true \
    --file-cache-timeout-in-seconds=120 \
    --log-level=LOG_WARNING \
    --config-file=/etc/bacula/azure-connection.cfg

echo "Azure Blob Storage mounted at ${MOUNT_POINT}"
SCRIPT

    chmod +x /opt/bacula/scripts/mount-azure-blob.sh

    log "Mount script created: /opt/bacula/scripts/mount-azure-blob.sh"
}

# Generate configuration summary
generate_config_summary() {
    log "Generating configuration summary"

    local storage_key
    storage_key=$(az storage account keys list --account-name "${AZURE_STORAGE_ACCOUNT}" --resource-group "${AZURE_RESOURCE_GROUP}" --query '[0].value' -o tsv)

    cat > /tmp/azure-config-summary.txt <<EOF
===========================================
Azure Blob Storage Configuration Summary
===========================================

Storage Account: ${AZURE_STORAGE_ACCOUNT}
Resource Group: ${AZURE_RESOURCE_GROUP}
Container: ${AZURE_CONTAINER_NAME}
Region: ${AZURE_REGION}
Replication: GRS (Geo-Redundant)

Encryption:
  - Encryption at rest: Enabled (Microsoft-managed keys)
  - TLS version: 1.3
  - HTTPS only: Yes

Lifecycle Policy:
  - Hot to Cool: ${HOT_TO_COOL_DAYS} days
  - Cool to Archive: ${COOL_TO_ARCHIVE_DAYS} days
  - Retention: ${DELETE_AFTER_DAYS} days

Features:
  - Blob versioning: Enabled
  - Soft delete: Enabled (30 days)
  - Change feed: Enabled
  - Public access: Disabled

Access Keys:
  - Primary key: ${storage_key:0:20}...
  - SAS token file: /tmp/azure-sas-token.txt

Bacula Configuration:
  Update bacula-sd-azure.conf with:
    Account: ${AZURE_STORAGE_ACCOUNT}
    Container: ${AZURE_CONTAINER_NAME}
    Access Key: [Use stored key]

===========================================
EOF

    cat /tmp/azure-config-summary.txt | tee -a "${LOG_FILE}"
}

# Main execution
main() {
    log "=== Azure Blob Storage Configuration Started ==="

    # Validate inputs
    if [[ -z "${AZURE_STORAGE_ACCOUNT}" ]] || [[ -z "${AZURE_RESOURCE_GROUP}" ]]; then
        log_error "AZURE_STORAGE_ACCOUNT and AZURE_RESOURCE_GROUP must be set"
        exit 1
    fi

    # Check prerequisites
    check_azure_cli || exit 1

    # Login to Azure
    azure_login

    # Create and configure storage
    create_storage_account
    enable_blob_versioning
    create_container
    configure_lifecycle_policy
    enable_soft_delete
    configure_encryption
    create_sas_token
    configure_monitoring

    # Create helper scripts
    create_mount_script

    # Generate summary
    generate_config_summary

    log "=== Azure Blob Storage Configuration Completed ==="
}

# Error handler
trap 'log_error "Azure configuration failed at line $LINENO"; exit 1' ERR

# Execute main
main "$@"
