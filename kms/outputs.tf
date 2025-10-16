output "cloud_provider" {
  description = "Cloud provider used"
  value       = var.cloud_provider
}

output "azure_tenant_id" {
  description = "Azure tenant ID"
  value       = module.azure_kms.tenant_id
}

output "client_id" {
  description = "Service principal client ID"
  value       = module.azure_kms.client_id
}

output "client_secret" {
  description = "Service principal client secret"
  value       = module.azure_kms.client_secret
  sensitive   = true
}

output "key_vault_name" {
  description = "Key vault name"
  value       = module.azure_kms.key_vault_name
}

output "key_name" {
  description = "Key name"
  value       = module.azure_kms.key_name
}

output "resource_group_name" {
  description = "Resource group name"
  value       = module.azure_kms.resource_group_name
}