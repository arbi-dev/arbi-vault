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

print_status "Setting up HashiCorp Vault with KMS auto-unseal..."

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    print_error "No terraform.tfstate found. Run './create-kms.sh' first."
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if docker compose is available
if ! docker compose version >/dev/null 2>&1; then
    print_error "docker compose is not available."
    exit 1
fi

# Detect provider from terraform outputs
PROVIDER=$(terraform output -raw cloud_provider 2>/dev/null || echo "unknown")

if [ "$PROVIDER" = "unknown" ]; then
    print_error "Could not detect cloud provider from terraform state"
    exit 1
fi

print_status "Detected provider: $PROVIDER"

# Extract credentials based on provider
case $PROVIDER in
    azure)
        print_status "Extracting Azure KMS credentials..."
        TENANT_ID=$(terraform output -raw azure_tenant_id 2>/dev/null)
        CLIENT_ID=$(terraform output -raw client_id 2>/dev/null)
        CLIENT_SECRET=$(terraform output -raw client_secret 2>/dev/null)
        KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null)
        KEY_NAME=$(terraform output -raw key_name 2>/dev/null)
        
        if [ -z "$TENANT_ID" ] || [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$KEY_VAULT_NAME" ] || [ -z "$KEY_NAME" ]; then
            print_error "Failed to extract Azure credentials from Terraform outputs"
            exit 1
        fi
        
# Helper function to mask sensitive values for display
mask_value() {
    local value="$1"
    if [ ${#value} -gt 12 ]; then
        echo "${value:0:8}...${value: -4}"
    else
        echo "***masked***"
    fi
}

        print_success "Azure credentials extracted successfully"
        echo "  Tenant ID: $(mask_value "$TENANT_ID")"
        echo "  Client ID: $(mask_value "$CLIENT_ID")"
        echo "  Key Vault: $KEY_VAULT_NAME"
        echo "  Key Name: $KEY_NAME"
        ;;
    aws)
        print_error "AWS provider not yet implemented"
        exit 1
        ;;
    gcp)
        print_error "GCP provider not yet implemented"
        exit 1
        ;;
    *)
        print_error "Unsupported provider: $PROVIDER"
        exit 1
        ;;
esac

# Create Vault configuration with actual credentials
print_status "Creating Vault configuration..."
cat > vault.hcl <<EOF
ui = true
disable_mlock = true

storage "raft" {
  path = "/vault/data"
  node_id = "node1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

seal "azurekeyvault" {
  tenant_id      = "$TENANT_ID"
  client_id      = "$CLIENT_ID"
  client_secret  = "$CLIENT_SECRET"
  vault_name     = "$KEY_VAULT_NAME"
  key_name       = "$KEY_NAME"
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
EOF

print_success "Vault configuration created"

# Check if container is already running
if docker ps --filter "name=vault-autounseal" --format "{{.Names}}" | grep -q vault-autounseal; then
    print_warning "Vault container is already running"
    print_status "Stopping existing container..."
    docker compose stop
fi

# Start Vault container (preserving volumes)
print_status "Starting Vault container with auto-unseal..."
docker compose up -d

# Wait for Vault to be ready
print_status "Waiting for Vault to be ready..."
VAULT_ADDR="http://localhost:8210"
export VAULT_ADDR

VAULT_READY=false
for i in {1..30}; do
    if curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        VAULT_READY=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Check if Vault is responding
if [ "$VAULT_READY" = "false" ]; then
    print_error "Vault is not responding after 60 seconds"
    docker compose logs vault
    exit 1
fi

print_success "Vault is responding"

# Check Vault status
print_status "Checking Vault initialization status..."
VAULT_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/init" | jq -r '.initialized' 2>/dev/null || echo "false")

if [ "$VAULT_STATUS" = "true" ]; then
    print_warning "Vault is already initialized"
    SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq -r '.sealed' 2>/dev/null || echo "true")
    
    if [ "$SEAL_STATUS" = "false" ]; then
        print_success "Vault is already unsealed with auto-unseal!"
    else
        print_error "Vault is sealed. Auto-unseal may not be working."
        exit 1
    fi
else
    # Initialize Vault
    print_status "Initializing Vault with auto-unseal..."
    INIT_RESPONSE=$(curl -s -X POST "$VAULT_ADDR/v1/sys/init" \
        -H "Content-Type: application/json" \
        -d '{"recovery_shares": 5, "recovery_threshold": 3}')
    
    if echo "$INIT_RESPONSE" | jq -e '.recovery_keys' >/dev/null 2>&1; then
        print_success "Vault initialized successfully with auto-unseal!"
        
        # Save recovery keys and root token
        echo "$INIT_RESPONSE" | jq -r '.recovery_keys[]' > recovery-keys.txt
        echo "$INIT_RESPONSE" | jq -r '.root_token' > root-token.txt
        
        print_success "Recovery keys saved to recovery-keys.txt"
        print_success "Root token saved to root-token.txt"
        
        # Check if Vault is unsealed
        SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq -r '.sealed' 2>/dev/null || echo "true")
        
        if [ "$SEAL_STATUS" = "false" ]; then
            print_success "Vault is unsealed automatically!"
        else
            print_error "Vault is still sealed after initialization. Auto-unseal failed."
            exit 1
        fi
    else
        print_error "Failed to initialize Vault"
        echo "Response: $INIT_RESPONSE"
        exit 1
    fi
fi

echo ""
echo "========================================"
echo -e "${GREEN}✅ VAULT SETUP COMPLETE!${NC}"
echo "========================================"
echo ""
echo "Your HashiCorp Vault is running with $PROVIDER KMS auto-unseal!"
echo ""
echo "Vault Details:"
echo "  URL: $VAULT_ADDR"
echo "  Status: Initialized and unsealed"
if [ -f "recovery-keys.txt" ]; then
    echo "  Recovery keys: recovery-keys.txt"
fi
if [ -f "root-token.txt" ]; then
    echo "  Root token: root-token.txt"
fi
echo ""
case $PROVIDER in
    azure)
        echo "Azure KMS Configuration:"
        echo "  Tenant ID: $(mask_value "$TENANT_ID")"
        echo "  Client ID: $(mask_value "$CLIENT_ID")"
        echo "  Key Vault: $KEY_VAULT_NAME"
        echo "  Key Name: $KEY_NAME"
        ;;
esac
echo ""
echo "To connect to Vault:"
echo "  export VAULT_ADDR=$VAULT_ADDR"
if [ -f "root-token.txt" ]; then
    echo "  export VAULT_TOKEN=\$(cat root-token.txt)"
fi
echo "  vault status"
echo ""
echo "Next steps:"
echo "  1. Run ./test-vault.sh to test auto-unseal functionality"
echo "  2. Explore Vault at $VAULT_ADDR (if UI is enabled)"
echo ""
echo "To stop Vault: docker compose stop"
echo "To clean up:   ./destroy-vault.sh"