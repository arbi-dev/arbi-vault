# HashiCorp Vault with Azure KMS Auto-Unseal

This project provides infrastructure-as-code and automation scripts to deploy HashiCorp Vault with Azure Key Vault auto-unseal functionality.

## Overview

- **Vault Setup**: Containerized HashiCorp Vault with Raft storage
- **Auto-Unseal**: Azure Key Vault integration for automatic unsealing
- **Infrastructure**: Terraform modules for Azure KMS resources
- **Automation**: Shell scripts for deployment, testing, and cleanup
- **Security**: RBAC-based permissions with minimal required access

## Prerequisites

### Required Tools
- [Terraform](https://terraform.io) (>= 1.0)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/) (logged in)
- [Docker](https://docker.com) with Docker Compose
- [jq](https://stedolan.github.io/jq/) for JSON processing
- bash shell

### Azure Requirements
- Azure subscription with appropriate permissions
- Ability to create:
  - Resource Groups (if using new shared resources)
  - Key Vaults (if using new shared resources)
  - Service Principals
  - RBAC role assignments

## Quick Start

1. **Clone and Setup**
   ```bash
   cd /path/to/arbi-vault/kms
   cp .env.example .env
   # Edit .env with your Azure subscription details
   ```

2. **Deploy Complete Stack**
   ```bash
   ./create-kms.sh      # Create KMS infrastructure
   ./test-kms.sh        # Verify KMS functionality
   ./create-vault.sh    # Deploy Vault with auto-unseal
   ./test-vault.sh      # Test auto-unseal functionality
   ```

3. **Access Vault**
   ```bash
   export VAULT_ADDR=http://localhost:8210
   export VAULT_TOKEN=$(cat root-token.txt)
   vault status
   ```

## Configuration

### Environment Variables (.env)
```bash
# Azure Subscription (required)
AZURE_SUBSCRIPTION_NAME="Your Azure Subscription"

# Deployment Configuration (auto-populated by scripts)
AZURE_TENANT_ID="..."
AZURE_CLIENT_ID="..."
AZURE_CLIENT_SECRET="..."
AZURE_VAULT_NAME="..."
AZURE_KEY_NAME="..."
```

### Terraform Variables (terraform.tfvars)
```hcl
# Deployment Configuration
deployment_domain = "dev-gpu"              # Unique identifier for this deployment
environment = "development"
cloud_provider = "azure"
location = "uksouth"

# Resource Configuration
use_existing_shared_resources = true       # Use existing RG/KV or create new
resource_group_name = "arbi-vault-shared-rg"
key_vault_name = "arbi-vault-shared-kv"
```

## Architecture

### Azure Resources Created
- **Service Principal**: Dedicated identity for Vault
- **Key Vault Key**: RSA-2048 key for encryption operations
- **RBAC Roles**: Minimal permissions for auto-unseal:
  - `Key Vault Crypto Service Encryption User`
  - `Key Vault Secrets User`
  - `Reader`

### Vault Configuration
- **Storage**: Raft backend for single-node deployment
- **Seal**: Azure Key Vault auto-unseal
- **API**: HTTP on port 8210 (localhost only)
- **UI**: Enabled at http://localhost:8210

## Scripts Reference

### Core Scripts

#### `./create-kms.sh`
Creates Azure KMS infrastructure with Terraform.

**Features:**
- Auto-detects existing shared resources
- Creates service principal with minimal permissions
- Generates encryption key for Vault
- Updates .env with credentials
- Detailed progress reporting

**Example:**
```bash
./create-kms.sh
```

#### `./test-kms.sh`
Tests KMS functionality before Vault deployment.

**Tests:**
- Service principal authentication
- Key vault access permissions
- Key wrap/unwrap operations (used by Vault)

**Example:**
```bash
./test-kms.sh
```

#### `./create-vault.sh`
Deploys HashiCorp Vault with auto-unseal configuration.

**Features:**
- Extracts KMS credentials from Terraform
- Creates Vault configuration with real credentials
- Initializes Vault with recovery keys
- Verifies auto-unseal functionality

**Example:**
```bash
./create-vault.sh
```

#### `./test-vault.sh`
Comprehensive auto-unseal testing.

**Tests:**
1. **Container Restart Test**: Verifies auto-unseal after `docker compose restart`
2. **Full Stop/Start Test**: Verifies auto-unseal after complete container restart
3. **Operations Test**: Verifies Vault functionality after auto-unseal

**Example:**
```bash
./test-vault.sh
```

### Cleanup Scripts

#### `./destroy-vault.sh`
Removes Vault deployment and data.

**Options:**
- `--force`: Skip confirmation prompts
- `--preserve-volumes`: Keep data volumes (default: destroys volumes)

**Examples:**
```bash
./destroy-vault.sh                    # Interactive cleanup (destroys volumes)
./destroy-vault.sh --force            # Silent cleanup (destroys volumes)
./destroy-vault.sh --preserve-volumes # Keep data volumes
```

#### `./destroy-kms.sh`
Removes KMS infrastructure while preserving shared resources.

**Options:**
- `--force`: Skip confirmation prompts  
- `--destroy-shared`: Remove shared resources (WARNING: affects other deployments)

**Examples:**
```bash
./destroy-kms.sh                 # Remove deployment-specific resources only
./destroy-kms.sh --destroy-shared # Remove ALL resources including shared RG/KV
```

## Security Model

### RBAC Permissions
The service principal receives minimal required permissions:

| Role | Scope | Purpose |
|------|-------|---------|
| Key Vault Crypto Service Encryption User | Key Vault | Wrap/unwrap operations |
| Key Vault Secrets User | Key Vault | Access key metadata |
| Reader | Key Vault | Read vault information |

### Credential Management
- **Service Principal**: Unique per deployment domain
- **Key**: Unique per deployment with timestamp
- **Secrets**: Stored in .env (git-ignored)
- **Vault Config**: Contains real credentials (git-ignored)

## Shared vs Dedicated Resources

### Shared Resources (Recommended)
- **Resource Group**: `arbi-vault-shared-rg`
- **Key Vault**: `arbi-vault-shared-kv`
- **Benefits**: Cost-effective, simpler management
- **Use Case**: Multiple environments/deployments

### Dedicated Resources
- **Resource Group**: `arbi-vault-{deployment-domain}-rg`
- **Key Vault**: `arbi-vault-{deployment-domain}-kv`
- **Benefits**: Complete isolation
- **Use Case**: Production environments, compliance requirements

## Troubleshooting

### Common Issues

#### "Access Denied" Errors
```bash
# Check RBAC role assignments
az role assignment list --assignee <service-principal-id> --scope <key-vault-id>

# Verify Key Vault permission model
az keyvault show --name <vault-name> --query "properties.enableRbacAuthorization"
```

#### Terraform State Issues
```bash
# Refresh state if resources changed outside Terraform
terraform refresh

# Import existing resources if needed
terraform import module.azure_kms.azurerm_key_vault.vault <key-vault-id>
```

#### Vault Sealed After Restart
```bash
# Check Vault logs
docker compose logs vault

# Verify auto-unseal configuration
curl -s http://localhost:8210/v1/sys/seal-status | jq
```

### Permission Propagation
Azure RBAC role assignments can take up to 10 minutes to propagate. The scripts include automatic wait times, but manual verification may be needed:

```bash
# Test key operations manually
az keyvault key show --vault-name <vault-name> --name <key-name>
```

## File Structure

```
kms/
├── README.md                    # This file
├── .env                        # Environment variables (git-ignored)
├── .gitignore                  # Git ignore patterns
├── main.tf                     # Main Terraform configuration
├── variables.tf                # Terraform input variables
├── outputs.tf                  # Terraform outputs
├── terraform.tfvars           # Terraform variable values (git-ignored)
├── modules/azure/              # Azure-specific Terraform module
│   ├── main.tf                # Azure resources definition
│   ├── variables.tf           # Module input variables
│   └── outputs.tf             # Module outputs
├── docker-compose.yml         # Vault container configuration
├── vault.hcl                  # Vault configuration (git-ignored)
├── create-kms.sh              # KMS infrastructure deployment
├── test-kms.sh                # KMS functionality testing
├── create-vault.sh            # Vault deployment
├── test-vault.sh              # Vault auto-unseal testing
├── destroy-vault.sh           # Vault cleanup
├── destroy-kms.sh             # KMS cleanup
├── recovery-keys.txt          # Vault recovery keys (git-ignored)
└── root-token.txt             # Vault root token (git-ignored)
```

## Development Workflow

### Complete Lifecycle Testing
```bash
# 1. Clean up any existing deployment
./destroy-vault.sh --force
./destroy-kms.sh --force

# 2. Deploy fresh infrastructure
./create-kms.sh

# 3. Verify KMS functionality
./test-kms.sh

# 4. Deploy Vault
./create-vault.sh

# 5. Test auto-unseal
./test-vault.sh
```

### Iterative Development
```bash
# Modify Vault configuration only
./destroy-vault.sh --force
./create-vault.sh
./test-vault.sh

# Modify KMS configuration
./destroy-vault.sh --force
./destroy-kms.sh --force
./create-kms.sh
./test-kms.sh
./create-vault.sh
./test-vault.sh
```

## Production Considerations

### Security
- Use dedicated Azure subscriptions for production
- Enable Key Vault firewall restrictions
- Use Azure Private Endpoints for Key Vault access
- Enable Vault audit logging
- Use TLS certificates for Vault API

### High Availability
- Deploy Vault in HA mode with multiple nodes
- Use Azure Storage Account for Raft snapshots
- Implement backup strategies for recovery keys
- Consider cross-region Key Vault replication

### Monitoring
- Enable Azure Monitor for Key Vault
- Configure Vault telemetry and metrics
- Set up alerting for seal/unseal events
- Monitor RBAC role assignment changes

## References

- [HashiCorp Vault Azure Auto-Unseal Guide](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-azure-keyvault)
- [Azure Key Vault RBAC Guide](https://docs.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)