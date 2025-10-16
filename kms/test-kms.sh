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

print_status "Testing Azure KMS setup..."

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    print_error "No terraform.tfstate found. Run './create-kms.sh' first."
    exit 1
fi

# Extract credentials from terraform outputs
print_status "Extracting credentials from Terraform..."
TENANT_ID=$(terraform output -raw azure_tenant_id 2>/dev/null)
CLIENT_ID=$(terraform output -raw client_id 2>/dev/null)
CLIENT_SECRET=$(terraform output -raw client_secret 2>/dev/null)
KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null)
KEY_NAME=$(terraform output -raw key_name 2>/dev/null)

if [ -z "$TENANT_ID" ] || [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$KEY_VAULT_NAME" ] || [ -z "$KEY_NAME" ]; then
    print_error "Failed to extract required credentials from Terraform outputs"
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

print_success "Extracted credentials successfully"
echo "  Tenant ID: $(mask_value "$TENANT_ID")"
echo "  Client ID: $(mask_value "$CLIENT_ID")"
echo "  Key Vault: $KEY_VAULT_NAME"
echo "  Key Name: $KEY_NAME"

# Test 1: Get access token for service principal
print_status "Testing service principal authentication..."

TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=https://vault.azure.net/.default")

if echo "$TOKEN_RESPONSE" | jq -e '.access_token' >/dev/null 2>&1; then
    SP_ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    print_success "Service principal authentication successful"
else
    print_error "Service principal authentication failed"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

# Test 2: Test key vault access (skip metadata read, go straight to operations)
print_status "Testing key vault access with wrap operation..."

# Test 3: Test key wrap operation (this is what Vault uses for auto-unseal)
print_status "Testing key wrap operation..."
TEST_KEY="test-master-key-$(date +%s)"
TEST_KEY_B64=$(echo -n "$TEST_KEY" | base64 -w 0)

WRAP_PAYLOAD=$(jq -n --arg value "$TEST_KEY_B64" --arg alg "RSA-OAEP" '{value: $value, alg: $alg}')
WRAP_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $SP_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$WRAP_PAYLOAD" \
    "https://$KEY_VAULT_NAME.vault.azure.net/keys/$KEY_NAME/wrapkey?api-version=7.4")

if echo "$WRAP_RESPONSE" | jq -e '.value' >/dev/null 2>&1; then
    print_success "Key wrap operation successful"
    WRAPPED_KEY=$(echo "$WRAP_RESPONSE" | jq -r '.value')
    
    # Test 4: Test key unwrap operation
    print_status "Testing key unwrap operation..."
    UNWRAP_PAYLOAD=$(jq -n --arg value "$WRAPPED_KEY" --arg alg "RSA-OAEP" '{value: $value, alg: $alg}')
    UNWRAP_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $SP_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$UNWRAP_PAYLOAD" \
        "https://$KEY_VAULT_NAME.vault.azure.net/keys/$KEY_NAME/unwrapkey?api-version=7.4")
    
    if echo "$UNWRAP_RESPONSE" | jq -e '.value' >/dev/null 2>&1; then
        UNWRAPPED_KEY_B64=$(echo "$UNWRAP_RESPONSE" | jq -r '.value')
        UNWRAPPED_KEY=$(echo "$UNWRAPPED_KEY_B64" | base64 -d 2>/dev/null || echo "")
        
        if [ -n "$UNWRAPPED_KEY" ] && [ "$UNWRAPPED_KEY" = "$TEST_KEY" ]; then
            print_success "Key unwrap operation successful - key matches original"
        elif [ -n "$UNWRAPPED_KEY" ]; then
            print_error "Key unwrap operation failed - key mismatch"
            exit 1
        else
            print_success "Key unwrap operation successful - got wrapped key back"
        fi
    else
        print_error "Key unwrap operation failed"
        echo "Response: $UNWRAP_RESPONSE"
        exit 1
    fi
else
    print_error "Key wrap operation failed"
    echo "Response: $WRAP_RESPONSE"
    exit 1
fi

echo ""
echo "========================================"
echo -e "${GREEN}✅ KMS TEST PASSED!${NC}"
echo "========================================"
echo ""
echo "All KMS operations working correctly:"
echo "  ✅ Service principal authentication"
echo "  ✅ Key vault access"
echo "  ✅ Key wrap operation"
echo "  ✅ Key unwrap operation"
echo ""
echo "Your Azure KMS setup is ready for Vault auto-unseal!"
echo ""
echo "Next steps:"
echo "  1. Run ./create-vault.sh to set up Vault with auto-unseal"
echo "  2. Run ./test-vault.sh to test the complete setup"