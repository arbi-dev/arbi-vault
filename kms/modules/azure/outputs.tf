output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "client_id" {
  description = "Service principal client ID"
  value       = azuread_application.vault.client_id
}

output "client_secret" {
  description = "Service principal client secret"
  value       = azuread_service_principal_password.vault.value
  sensitive   = true
}

output "key_vault_name" {
  description = "Key vault name"
  value       = var.key_vault_name
}

output "key_vault_id" {
  description = "Key vault ID"
  value       = local.key_vault_id
}

output "key_vault_uri" {
  description = "Key vault URI"
  value       = local.key_vault_uri
}

output "key_name" {
  description = "Key name"
  value       = azurerm_key_vault_key.vault.name
}

output "key_id" {
  description = "Key ID"
  value       = azurerm_key_vault_key.vault.id
}

output "resource_group_name" {
  description = "Resource group name"
  value       = local.resource_group_name
}

output "service_principal_name" {
  description = "Service principal name"
  value       = local.service_principal_name
}