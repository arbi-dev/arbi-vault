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
REMOVE_VOLUMES=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --preserve-volumes)
            REMOVE_VOLUMES=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force             Skip confirmation prompts"
            echo "  --preserve-volumes  Preserve Docker volumes (by default volumes are destroyed)"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_status "Cleaning up Vault client settings..."

if [ "$FORCE" = "false" ]; then
    echo ""
    print_warning "This will remove:"
    echo "  • Vault Docker container"
    echo "  • Vault configuration files"
    echo "  • Recovery keys and root token"
    if [ "$REMOVE_VOLUMES" = "true" ]; then
        echo "  • Docker volumes (ALL VAULT DATA WILL BE LOST)"
    else
        echo "  • Docker volumes will be PRESERVED"
    fi
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled"
        exit 0
    fi
fi

# Stop and remove containers
print_status "Stopping Vault containers..."
if docker compose ps --services | grep -q vault; then
    if [ "$REMOVE_VOLUMES" = "true" ]; then
        docker compose down -v
        print_success "Vault containers and volumes removed"
    else
        docker compose down
        print_success "Vault containers removed (volumes preserved)"
    fi
else
    print_warning "No running Vault containers found"
fi

# Remove any dangling containers with vault-autounseal name
print_status "Cleaning up any remaining containers..."
if docker ps -a --filter "name=vault-autounseal" --format "{{.Names}}" | grep -q vault-autounseal; then
    docker rm -f vault-autounseal 2>/dev/null || true
    print_success "Removed vault-autounseal container"
fi

# Clean up local files
print_status "Cleaning up local configuration files..."

FILES_TO_REMOVE=(
    "vault.hcl"
    "recovery-keys.txt"
    "root-token.txt"
    "vault-temp.hcl"
    "docker-compose-temp.yml"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        print_success "Removed $file"
    fi
done

# Clean up any temp directories
if [ -d "vault-temp.hcl" ]; then
    rm -rf "vault-temp.hcl"
    print_success "Removed vault-temp.hcl directory"
fi

# Show remaining volumes
print_status "Checking remaining Docker volumes..."
VAULT_VOLUMES=$(docker volume ls --filter "name=kms_vault-data" --format "{{.Name}}" 2>/dev/null || true)
if [ -n "$VAULT_VOLUMES" ]; then
    if [ "$REMOVE_VOLUMES" = "true" ]; then
        print_success "All volumes removed"
    else
        print_warning "Vault data volumes preserved:"
        echo "$VAULT_VOLUMES" | while read -r volume; do
            echo "  • $volume"
        done
        echo ""
        print_status "To remove data volumes later, run: docker volume rm $VAULT_VOLUMES"
    fi
else
    print_success "No Vault volumes found"
fi

echo ""
echo "========================================"
echo -e "${GREEN}✅ VAULT CLEANUP COMPLETE!${NC}"
echo "========================================"
echo ""
echo "Cleaned up:"
echo "  ✅ Vault Docker containers"
echo "  ✅ Configuration files"
echo "  ✅ Recovery keys and tokens"
if [ "$REMOVE_VOLUMES" = "true" ]; then
    echo "  ✅ Docker volumes (data destroyed)"
else
    echo "  ⚠️  Docker volumes preserved"
fi
echo ""
echo "The KMS infrastructure remains intact."
echo "You can recreate Vault by running: ./create-vault.sh"