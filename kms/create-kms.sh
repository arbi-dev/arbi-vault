#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Load environment variables
if [ -f ".env" ]; then
    print_status "Loading environment variables from .env..."
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
DEPLOYMENT_DOMAIN="dev-gpu"
RESOURCE_GROUP_NAME="arbi-vault-shared-rg"
KEY_VAULT_NAME="arbi-vault-shared-kv"

print_status "Setting up KMS infrastructure for deployment domain: $DEPLOYMENT_DOMAIN"

# Check if Azure CLI is installed and logged in
if ! command -v az >/dev/null 2>&1; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! az account show >/dev/null 2>&1; then
    print_error "Not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform >/dev/null 2>&1; then
    print_error "Terraform is not installed. Please install it first."
    exit 1
fi

# Auto-detect existing shared resources
print_status "Checking for existing shared resources..."

EXISTING_RG=$(az group show --name "$RESOURCE_GROUP_NAME" --query "name" -o tsv 2>/dev/null || echo "")
EXISTING_KV=$(az keyvault show --name "$KEY_VAULT_NAME" --query "name" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_RG" ] && [ -n "$EXISTING_KV" ]; then
    print_success "Found existing shared resources:"
    print_success "  Resource Group: $EXISTING_RG"
    print_success "  Key Vault: $EXISTING_KV"
    USE_EXISTING="true"
else
    print_status "No existing shared resources found, will create new ones"
    USE_EXISTING="false"
fi

# Initialize Terraform
print_status "Initializing Terraform..."
if terraform init; then
    print_success "Terraform initialization completed"
else
    print_error "Terraform initialization failed"
    exit 1
fi

# Generate terraform.tfvars
print_status "Generating terraform.tfvars..."
cat > terraform.tfvars <<EOF
# Deployment Configuration
deployment_domain = "$DEPLOYMENT_DOMAIN"
environment = "development"

# Azure Configuration
cloud_provider = "azure"
location = "uksouth"

# Resource Configuration
use_existing_shared_resources = $USE_EXISTING
resource_group_name = "$RESOURCE_GROUP_NAME"
key_vault_name = "$KEY_VAULT_NAME"
EOF

# Plan and apply
print_status "Planning Terraform deployment..."
if terraform plan; then
    print_success "Terraform plan completed successfully"
else
    print_error "Terraform plan failed"
    exit 1
fi

print_status "Applying Terraform configuration..."
if terraform apply -auto-approve; then
    print_success "Terraform apply completed successfully"
else
    print_error "Terraform apply failed"
    exit 1
fi

# Extract outputs
print_status "Extracting deployment information..."
print_status "  → Extracting tenant ID..."
TENANT_ID=$(terraform output -raw azure_tenant_id 2>/dev/null || echo "")
print_status "  → Extracting client ID..."
CLIENT_ID=$(terraform output -raw client_id 2>/dev/null || echo "")
print_status "  → Extracting client secret..."
CLIENT_SECRET=$(terraform output -raw client_secret 2>/dev/null || echo "")
print_status "  → Extracting key vault name..."
KEY_VAULT_NAME_OUTPUT=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
print_status "  → Extracting key name..."
KEY_NAME=$(terraform output -raw key_name 2>/dev/null || echo "")

# Helper function to mask sensitive values for display
mask_value() {
    local value="$1"
    if [ ${#value} -gt 12 ]; then
        echo "${value:0:8}...${value: -4}"
    else
        echo "***masked***"
    fi
}

if [ -z "$TENANT_ID" ] || [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    print_error "Failed to extract required outputs from Terraform"
    exit 1
fi

# Update .env file with KMS credentials
print_status "Updating .env file with KMS credentials..."
print_status "  → Updating tenant ID..."
if grep -q "AZURE_TENANT_ID=" .env; then
    sed -i "s/AZURE_TENANT_ID=.*/AZURE_TENANT_ID=\"$TENANT_ID\"/" .env
else
    echo "AZURE_TENANT_ID=\"$TENANT_ID\"" >> .env
fi

print_status "  → Updating client ID..."
if grep -q "AZURE_CLIENT_ID=" .env; then
    sed -i "s/AZURE_CLIENT_ID=.*/AZURE_CLIENT_ID=\"$CLIENT_ID\"/" .env
else
    echo "AZURE_CLIENT_ID=\"$CLIENT_ID\"" >> .env
fi

print_status "  → Updating client secret..."
if grep -q "AZURE_CLIENT_SECRET=" .env; then
    sed -i "s/AZURE_CLIENT_SECRET=.*/AZURE_CLIENT_SECRET=\"$CLIENT_SECRET\"/" .env
else
    echo "AZURE_CLIENT_SECRET=\"$CLIENT_SECRET\"" >> .env
fi

print_status "  → Updating vault name..."
if grep -q "AZURE_VAULT_NAME=" .env; then
    sed -i "s/AZURE_VAULT_NAME=.*/AZURE_VAULT_NAME=\"$KEY_VAULT_NAME_OUTPUT\"/" .env
else
    echo "AZURE_VAULT_NAME=\"$KEY_VAULT_NAME_OUTPUT\"" >> .env
fi

print_status "  → Updating key name..."
if grep -q "AZURE_KEY_NAME=" .env; then
    sed -i "s/AZURE_KEY_NAME=.*/AZURE_KEY_NAME=\"$KEY_NAME\"/" .env
else
    echo "AZURE_KEY_NAME=\"$KEY_NAME\"" >> .env
fi

print_success "Environment file updated successfully"

echo ""
echo "========================================"
echo -e "${GREEN}✅ KMS SETUP COMPLETE!${NC}"
echo "========================================"
echo ""
echo "Azure KMS Configuration:"
echo "  Tenant ID: $(mask_value "$TENANT_ID")"
echo "  Client ID: $(mask_value "$CLIENT_ID")"
echo "  Key Vault: $KEY_VAULT_NAME_OUTPUT"
echo "  Key Name: $KEY_NAME"
echo "  Deployment Domain: $DEPLOYMENT_DOMAIN"
echo ""
echo "Credentials have been saved to .env file"
echo ""
echo "Next steps:"
echo "  1. Run ./test-kms.sh to test the KMS setup"
echo "  2. Run ./create-vault.sh to set up Vault with auto-unseal"