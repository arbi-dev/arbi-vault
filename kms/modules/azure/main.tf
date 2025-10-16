data "azurerm_client_config" "current" {}

locals {
  deployment_id = formatdate("YYMMDDHHmmss", timestamp())
  service_principal_name = "${var.service_principal_prefix}-${var.deployment_domain}-${local.deployment_id}"
  key_name = "${var.key_name_prefix}-${var.deployment_domain}-${local.deployment_id}"
  
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "arbi-vault"
    DeploymentDomain = var.deployment_domain
    DeploymentId = local.deployment_id
  })
}

# Resource Group
resource "azurerm_resource_group" "vault" {
  count    = var.use_existing_shared_resources ? 0 : 1
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

data "azurerm_resource_group" "vault" {
  count = var.use_existing_shared_resources ? 1 : 0
  name  = var.resource_group_name
}

locals {
  resource_group_name = var.use_existing_shared_resources ? data.azurerm_resource_group.vault[0].name : azurerm_resource_group.vault[0].name
  resource_group_id   = var.use_existing_shared_resources ? data.azurerm_resource_group.vault[0].id : azurerm_resource_group.vault[0].id
}

# Key Vault
resource "azurerm_key_vault" "vault" {
  count               = var.use_existing_shared_resources ? 0 : 1
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Create",
      "Delete",
      "Get",
      "List",
      "Update",
      "Purge",
      "Recover",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]
  }
  
  tags = local.common_tags
}

data "azurerm_key_vault" "vault" {
  count               = var.use_existing_shared_resources ? 1 : 0
  name                = var.key_vault_name
  resource_group_name = local.resource_group_name
}

locals {
  key_vault_id  = var.use_existing_shared_resources ? data.azurerm_key_vault.vault[0].id : azurerm_key_vault.vault[0].id
  key_vault_uri = var.use_existing_shared_resources ? data.azurerm_key_vault.vault[0].vault_uri : azurerm_key_vault.vault[0].vault_uri
}

# Service Principal
resource "azuread_application" "vault" {
  display_name = local.service_principal_name
  
  tags = [
    "Project:arbi-vault",
    "Environment:${var.environment}",
    "DeploymentDomain:${var.deployment_domain}",
    "ManagedBy:terraform"
  ]
}

resource "azuread_service_principal" "vault" {
  client_id = azuread_application.vault.client_id
  
  tags = [
    "Project:arbi-vault",
    "Environment:${var.environment}",
    "DeploymentDomain:${var.deployment_domain}",
    "ManagedBy:terraform"
  ]
}

resource "azuread_service_principal_password" "vault" {
  service_principal_id = azuread_service_principal.vault.object_id
  end_date_relative    = "8760h" # 1 year
}

# RBAC role assignments for Service Principal (per HashiCorp documentation)
resource "azurerm_role_assignment" "sp_crypto_service_encryption_user" {
  scope                = local.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azuread_service_principal.vault.object_id
  
  depends_on = [
    azurerm_key_vault.vault,
    data.azurerm_key_vault.vault
  ]
}

resource "azurerm_role_assignment" "sp_secrets_user" {
  scope                = local.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.vault.object_id
  
  depends_on = [
    azurerm_key_vault.vault,
    data.azurerm_key_vault.vault
  ]
}

resource "azurerm_role_assignment" "sp_reader" {
  scope                = local.key_vault_id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.vault.object_id
  
  depends_on = [
    azurerm_key_vault.vault,
    data.azurerm_key_vault.vault
  ]
}

# Wait for RBAC role assignment propagation
resource "time_sleep" "wait_for_rbac" {
  create_duration = "45s"
  
  depends_on = [
    azurerm_role_assignment.sp_crypto_service_encryption_user,
    azurerm_role_assignment.sp_secrets_user,
    azurerm_role_assignment.sp_reader
  ]
}

# Key for Vault auto-unseal
resource "azurerm_key_vault_key" "vault" {
  name         = local.key_name
  key_vault_id = local.key_vault_id
  key_type     = "RSA"
  key_size     = 2048
  
  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_key_vault.vault,
    data.azurerm_key_vault.vault,
    azurerm_role_assignment.sp_crypto_service_encryption_user,
    azurerm_role_assignment.sp_secrets_user,
    azurerm_role_assignment.sp_reader,
    time_sleep.wait_for_rbac
  ]
}