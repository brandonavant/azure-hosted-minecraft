#!/usr/bin/env bash

set -euo pipefail
trap 'echo "ERROR: bootstrap failed at line ${LINENO}" >&2' ERR

echo "Starting OpenTofu backend bootstrap..."

[[ -f .env ]] && source .env

# Ensure that the required environment variables are set
required_vars=("TF_BACKEND_SUBSCRIPTION_ID" "TF_BACKEND_LOCATION" "TF_BACKEND_PROJECT_NAME" "TF_BACKEND_TEAM_NAME")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Environment variable ${var} is not set."
        exit 1
    fi
done

normalize_storage_account_name() {
    local raw_name="$1"
    local normalized

    normalized=$(echo -n "${raw_name}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

    if [[ ${#normalized} -lt 3 || ${#normalized} -gt 24 ]]; then
        echo "ERROR: Storage account name '${raw_name}' is invalid after normalization (must be 3-24 chars, got ${#normalized})." >&2
        exit 1
    fi

    echo "${normalized}"
}

# Ensure AZ CLI is installed
if ! command -v az &> /dev/null; then
    echo "ERROR: Azure CLI (az) is not installed. Please install it and try again."
    exit 1
fi

# Login to Azure if not already logged in
if ! az account show &> /dev/null; then
    echo "Logging in to Azure..."
    az login
fi

# Set the subscription
echo "Setting Azure subscription to ${TF_BACKEND_SUBSCRIPTION_ID}..."
az account set --subscription "${TF_BACKEND_SUBSCRIPTION_ID}"

# Create resource group for OpenTofu backend
CREATED_BY="opentofu-bootstrap-script"
RG_NAME="rg-${TF_BACKEND_TEAM_NAME}-${TF_BACKEND_PROJECT_NAME}-tfstate"
RAW_STORAGE_ACCOUNT_NAME="st${TF_BACKEND_TEAM_NAME}${TF_BACKEND_PROJECT_NAME}tfstate"
STORAGE_ACCOUNT_NAME=$(normalize_storage_account_name "${RAW_STORAGE_ACCOUNT_NAME}")
echo "Creating resource group ${RG_NAME} in ${TF_BACKEND_LOCATION}..."
if az group exists --name "${RG_NAME}" | grep -q true; then
    echo "Resource group ${RG_NAME} already exists; skipping create."
else
    az group create \
        --name "${RG_NAME}" \
        --location "${TF_BACKEND_LOCATION}" \
        --tags "project=${TF_BACKEND_PROJECT_NAME}" "createdBy=${CREATED_BY}"
fi

echo "Using storage account name ${STORAGE_ACCOUNT_NAME} (normalized from ${RAW_STORAGE_ACCOUNT_NAME})"
if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RG_NAME}" > /dev/null 2>&1; then
    echo "Storage account ${STORAGE_ACCOUNT_NAME} already exists; skipping create."
else
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RG_NAME}" \
        --location "${TF_BACKEND_LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags "project=${TF_BACKEND_PROJECT_NAME}" "createdBy=${CREATED_BY}"
fi

# Create blob containers for OpenTofu state; one for dev and one for prod
for env_name in "dev" "prod"; do
    CONTAINER_NAME="tfstate-${env_name}"
    echo "Ensuring blob container ${CONTAINER_NAME} exists in storage account ${STORAGE_ACCOUNT_NAME}..."
    if az storage container show \
        --name "${CONTAINER_NAME}" \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --auth-mode login \
        > /dev/null 2>&1; then
        echo "Blob container ${CONTAINER_NAME} already exists; skipping create."
    else
        az storage container create \
            --name "${CONTAINER_NAME}" \
            --account-name "${STORAGE_ACCOUNT_NAME}" \
            --auth-mode login \
            --public-access off \
            --only-show-errors
    fi
done

echo "OpenTofu backend bootstrap completed successfully."
echo "Resource Group: ${RG_NAME}"
echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
echo "Blob Containers: tfstate-dev, tfstate-prod"
echo "Subscription ID: ${TF_BACKEND_SUBSCRIPTION_ID}"
echo "Location: ${TF_BACKEND_LOCATION}"
