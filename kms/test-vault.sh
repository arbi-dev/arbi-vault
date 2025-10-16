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

print_status "Testing HashiCorp Vault auto-unseal functionality..."

# Check if Vault is running
VAULT_ADDR="http://localhost:8210"
export VAULT_ADDR

if ! curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
    print_error "Vault is not running or not accessible at $VAULT_ADDR"
    print_error "Run './create-vault.sh' first to set up Vault"
    exit 1
fi

print_success "Vault is accessible at $VAULT_ADDR"

# Check if docker compose is available
if ! docker compose version >/dev/null 2>&1; then
    print_error "docker compose is not available."
    exit 1
fi

# Check initial status
print_status "Checking initial Vault status..."
INITIAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq '{initialized: .initialized, sealed: .sealed, type: .type}')
echo "$INITIAL_STATUS" | jq .

INITIALIZED=$(echo "$INITIAL_STATUS" | jq -r '.initialized')
SEALED=$(echo "$INITIAL_STATUS" | jq -r '.sealed')
SEAL_TYPE=$(echo "$INITIAL_STATUS" | jq -r '.type')

if [ "$INITIALIZED" != "true" ]; then
    print_error "Vault is not initialized. Run './create-vault.sh' first."
    exit 1
fi

if [ "$SEALED" = "true" ]; then
    print_error "Vault is currently sealed. This suggests auto-unseal is not working."
    exit 1
fi

if [ "$SEAL_TYPE" = "null" ] || [ -z "$SEAL_TYPE" ]; then
    print_warning "Vault does not appear to be using auto-unseal (seal type: $SEAL_TYPE)"
fi

print_success "Initial state: Vault is initialized and unsealed"
echo "  Seal type: $SEAL_TYPE"

# Test 1: Restart the container to test auto-unseal
print_status "Test 1: Restarting Vault container to test auto-unseal..."

# Capture container start time before restart
START_TIME_BEFORE=$(docker inspect vault-autounseal --format='{{.State.StartedAt}}')
print_status "Container start time before restart: $START_TIME_BEFORE"

docker compose restart vault

print_status "Waiting for Vault to restart..."
sleep 10

# Verify container actually restarted by checking new start time
START_TIME_AFTER=$(docker inspect vault-autounseal --format='{{.State.StartedAt}}')
print_status "Container start time after restart: $START_TIME_AFTER"

if [ "$START_TIME_BEFORE" != "$START_TIME_AFTER" ]; then
    print_success "✅ Container successfully restarted (start time changed)"
else
    print_error "❌ Container may not have restarted (start time unchanged)"
    exit 1
fi

# Wait for Vault to be ready
VAULT_READY=false
for i in {1..15}; do
    if curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        VAULT_READY=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$VAULT_READY" = "false" ]; then
    print_error "Vault is not responding after restart"
    docker compose logs vault
    exit 1
fi

# Check seal status after restart
print_status "Checking seal status after restart..."
RESTART_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq '{initialized: .initialized, sealed: .sealed, type: .type}')
echo "$RESTART_STATUS" | jq .

SEALED_AFTER_RESTART=$(echo "$RESTART_STATUS" | jq -r '.sealed')

if [ "$SEALED_AFTER_RESTART" = "false" ]; then
    print_success "✅ Auto-unseal working! Vault unsealed automatically after restart"
else
    print_error "❌ Auto-unseal failed! Vault is sealed after restart"
    exit 1
fi

# Test 2: Stop and start (more thorough test)
print_status "Test 2: Stopping and starting Vault completely..."

# Capture container ID before stop
CONTAINER_ID_BEFORE_STOP=$(docker ps --filter "name=vault-autounseal" --format "{{.ID}}")
print_status "Container ID before stop: $CONTAINER_ID_BEFORE_STOP"

docker compose stop

# Verify container is stopped
STOPPED_CONTAINERS=$(docker ps -a --filter "name=vault-autounseal" --filter "status=exited" --format "{{.ID}}")
if [ -n "$STOPPED_CONTAINERS" ]; then
    print_success "✅ Container successfully stopped"
else
    print_error "❌ Container may not have stopped properly"
    exit 1
fi

print_status "Starting Vault again..."
docker compose start

print_status "Waiting for Vault to start..."
sleep 15

# Verify container started with same ID (since we used start, not up)
CONTAINER_ID_AFTER_START=$(docker ps --filter "name=vault-autounseal" --format "{{.ID}}")
print_status "Container ID after start: $CONTAINER_ID_AFTER_START"

if [ "$CONTAINER_ID_BEFORE_STOP" = "$CONTAINER_ID_AFTER_START" ]; then
    print_success "✅ Container successfully restarted (same container ID)"
else
    print_error "❌ Different container started (expected same ID)"
    exit 1
fi

# Wait for Vault to be ready
VAULT_READY=false
for i in {1..15}; do
    if curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        VAULT_READY=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$VAULT_READY" = "false" ]; then
    print_error "Vault is not responding after full restart"
    docker compose logs vault
    exit 1
fi

# Check seal status after full restart
print_status "Checking seal status after full restart..."
FULL_RESTART_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq '{initialized: .initialized, sealed: .sealed, type: .type}')
echo "$FULL_RESTART_STATUS" | jq .

SEALED_AFTER_FULL_RESTART=$(echo "$FULL_RESTART_STATUS" | jq -r '.sealed')

if [ "$SEALED_AFTER_FULL_RESTART" = "false" ]; then
    print_success "✅ Auto-unseal working! Vault unsealed automatically after full restart"
else
    print_error "❌ Auto-unseal failed! Vault is sealed after full restart"
    exit 1
fi

# Test 3: Verify Vault operations still work
print_status "Test 3: Verifying Vault operations after auto-unseal..."

if [ -f "root-token.txt" ]; then
    ROOT_TOKEN=$(cat root-token.txt)
    export VAULT_TOKEN="$ROOT_TOKEN"
    
    # Test basic Vault operations using sys endpoints (always available)
    
    # Test 1: Check auth methods
    AUTH_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/auth" \
        -H "X-Vault-Token: $ROOT_TOKEN")
    
    if echo "$AUTH_RESPONSE" | jq -e '.["token/"]' >/dev/null 2>&1; then
        print_success "✅ Auth methods accessible"
    else
        print_error "❌ Cannot access auth methods"
        exit 1
    fi
    
    # Test 2: Check mounts
    MOUNTS_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/mounts" \
        -H "X-Vault-Token: $ROOT_TOKEN")
    
    if echo "$MOUNTS_RESPONSE" | jq -e '.["sys/"]' >/dev/null 2>&1; then
        print_success "✅ System mounts accessible"
    else
        print_error "❌ Cannot access system mounts"
        exit 1
    fi
    
    # Test 3: Check policies (using correct endpoint)
    POLICIES_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/policy" \
        -H "X-Vault-Token: $ROOT_TOKEN")
    
    if echo "$POLICIES_RESPONSE" | jq -e '.policies' >/dev/null 2>&1; then
        POLICY_COUNT=$(echo "$POLICIES_RESPONSE" | jq -r '.policies | length')
        print_success "✅ Policies accessible (found $POLICY_COUNT policies)"
    else
        print_error "❌ Cannot access policies"
        exit 1
    fi
    
    # Test 4: Verify token is valid by checking self
    TOKEN_SELF_RESPONSE=$(curl -s "$VAULT_ADDR/v1/auth/token/lookup-self" \
        -H "X-Vault-Token: $ROOT_TOKEN")
    
    if echo "$TOKEN_SELF_RESPONSE" | jq -e '.data.id' >/dev/null 2>&1; then
        print_success "✅ Root token valid and functional"
    else
        print_error "❌ Root token validation failed"
        exit 1
    fi
    
    print_success "✅ All Vault operations working correctly after auto-unseal"
else
    print_warning "No root token found, skipping operation verification"
fi

# Final status report
print_status "Final Vault status:"
FINAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq '{initialized: .initialized, sealed: .sealed, type: .type, version: .version}')
echo "$FINAL_STATUS" | jq .

echo ""
echo "========================================"
echo -e "${GREEN}✅ VAULT AUTO-UNSEAL TEST PASSED!${NC}"
echo "========================================"
echo ""
echo "Auto-unseal functionality verified:"
echo "  ✅ Vault automatically unseals after container restart"
echo "  ✅ Vault automatically unseals after full stop/start"
echo "  ✅ Vault operations work correctly after auto-unseal"
echo ""
echo "Your HashiCorp Vault with KMS auto-unseal is working perfectly!"
echo ""
echo "Vault URL: $VAULT_ADDR"
if [ -f "recovery-keys.txt" ]; then
    echo "Recovery keys: recovery-keys.txt"
fi
if [ -f "root-token.txt" ]; then
    echo "Root token: root-token.txt"
fi
echo ""
echo "To connect to Vault:"
echo "  export VAULT_ADDR=$VAULT_ADDR"
if [ -f "root-token.txt" ]; then
    echo "  export VAULT_TOKEN=\$(cat root-token.txt)"
fi
echo "  vault status"