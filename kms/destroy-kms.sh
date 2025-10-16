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

# Parse command line arguments
FORCE=false
DESTROY_SHARED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --destroy-shared)
            DESTROY_SHARED=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force           Skip confirmation prompts"
            echo "  --destroy-shared  Destroy shared resources (WARNING: affects other deployments)"
            echo "  -h, --help        Show this help message"
            echo ""
            echo "This script will destroy:"
            echo "  • Service principal and credentials for this deployment"
            echo "  • Vault key for this deployment"
            echo "  • Terraform state and configuration"
            echo ""
            echo "By default, shared resources (Resource Group, Key Vault) are preserved."
            echo "Use --destroy-shared to remove them (only if no other deployments exist)."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_status "Preparing to destroy KMS infrastructure..."

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    print_warning "No terraform.tfstate found. Nothing to destroy."
    exit 0
fi

# Extract deployment information
DEPLOYMENT_DOMAIN=$(terraform output -raw deployment_domain 2>/dev/null || echo "unknown")
CLOUD_PROVIDER=$(terraform output -raw cloud_provider 2>/dev/null || echo "unknown")

# If terraform.tfvars is missing, try to recreate it from terraform outputs
if [ ! -f "terraform.tfvars" ] && [ -f "terraform.tfstate" ]; then
    print_status "Recreating terraform.tfvars from state..."
    
    USE_EXISTING=$(terraform show -json | jq -r '.values.root_module.child_modules[0].resources[] | select(.type=="azurerm_resource_group") | length' 2>/dev/null || echo "1")
    if [ "$USE_EXISTING" = "0" ]; then
        USE_EXISTING_BOOL="false"
    else
        USE_EXISTING_BOOL="true"
    fi
    
    cat > terraform.tfvars <<EOF
deployment_domain = "$DEPLOYMENT_DOMAIN"
environment = "development"
cloud_provider = "$CLOUD_PROVIDER"
location = "uksouth"
use_existing_shared_resources = $USE_EXISTING_BOOL
resource_group_name = "arbi-vault-shared-rg"
key_vault_name = "arbi-vault-shared-kv"
EOF
    print_success "Recreated terraform.tfvars"
fi

if [ "$FORCE" = "false" ]; then
    echo ""
    print_warning "This will destroy KMS infrastructure for:"
    echo "  • Deployment Domain: $DEPLOYMENT_DOMAIN"
    echo "  • Cloud Provider: $CLOUD_PROVIDER"
    echo ""
    print_warning "Resources to be destroyed:"
    echo "  • Service principal and credentials"
    echo "  • Vault encryption key"
    echo "  • Terraform state files"
    
    if [ "$DESTROY_SHARED" = "true" ]; then
        echo "  • Shared resources (Resource Group, Key Vault)"
        print_error "WARNING: This will affect ALL deployments using shared resources!"
    else
        echo "  • Shared resources will be PRESERVED"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled"
        exit 0
    fi
fi

# Update terraform variables to control what gets destroyed
if [ -f "terraform.tfvars" ]; then
    print_status "Updating terraform configuration..."
    
    # If destroying shared resources, set use_existing_shared_resources to false
    if [ "$DESTROY_SHARED" = "true" ]; then
        sed -i 's/use_existing_shared_resources = true/use_existing_shared_resources = false/' terraform.tfvars
        print_warning "Set to destroy shared resources"
    else
        sed -i 's/use_existing_shared_resources = false/use_existing_shared_resources = true/' terraform.tfvars
        print_success "Set to preserve shared resources"
    fi
fi

# Ensure terraform is initialized
print_status "Ensuring terraform is initialized..."
terraform init >/dev/null 2>&1 || {
    print_error "Failed to initialize terraform"
    exit 1
}

# Run terraform destroy
print_status "Running terraform destroy..."
if [ "$FORCE" = "true" ]; then
    timeout 300 terraform destroy -auto-approve || {
        print_error "Terraform destroy timed out or failed"
        print_warning "You may need to manually clean up resources in Azure"
        exit 1
    }
else
    timeout 300 terraform destroy || {
        print_error "Terraform destroy timed out or failed"
        print_warning "You may need to manually clean up resources in Azure"
        exit 1
    }
fi

# Clean up terraform files
print_status "Cleaning up terraform files..."
FILES_TO_REMOVE=(
    "terraform.tfstate"
    "terraform.tfstate.backup"
    "terraform.tfstate.*.backup"
    "terraform.tfvars"
    ".terraform.tfstate.lock.info"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if ls $file 1> /dev/null 2>&1; then
        rm -f $file
        print_success "Removed $file"
    fi
done

# Clean up terraform directory
if [ -d ".terraform" ]; then
    rm -rf ".terraform"
    print_success "Removed .terraform directory"
fi

# Clean up credentials from .env file
if [ -f ".env" ]; then
    print_status "Cleaning up .env file..."
    
    # Remove KMS-specific entries
    sed -i '/^AZURE_CLIENT_ID=/d' .env
    sed -i '/^AZURE_CLIENT_SECRET=/d' .env
    sed -i '/^AZURE_VAULT_NAME=/d' .env
    sed -i '/^AZURE_KEY_NAME=/d' .env
    
    print_success "Removed KMS credentials from .env"
fi

echo ""
echo "========================================"
echo -e "${GREEN}✅ KMS CLEANUP COMPLETE!${NC}"
echo "========================================"
echo ""
echo "Destroyed resources:"
echo "  ✅ Service principal for deployment: $DEPLOYMENT_DOMAIN"
echo "  ✅ Vault encryption key"
echo "  ✅ Terraform state and configuration"

if [ "$DESTROY_SHARED" = "true" ]; then
    echo "  ✅ Shared resources (Resource Group, Key Vault)"
    print_warning "All shared resources have been destroyed!"
else
    echo "  ⚠️  Shared resources preserved for other deployments"
fi

echo ""
echo "KMS infrastructure for deployment '$DEPLOYMENT_DOMAIN' has been removed."
echo ""
echo "To recreate: ./create-kms.sh"