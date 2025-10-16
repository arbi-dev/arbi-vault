variable "deployment_domain" {
  description = "Deployment domain identifier (e.g., dev-gpu, staging, production)"
  type        = string
  validation {
    condition     = length(var.deployment_domain) >= 1 && length(var.deployment_domain) <= 50
    error_message = "Deployment domain must be between 1 and 50 characters."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "uksouth"
}

variable "use_existing_shared_resources" {
  description = "Whether to use existing shared resources"
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "key_vault_name" {
  description = "Name of the key vault"
  type        = string
}

variable "service_principal_prefix" {
  description = "Prefix for service principal name"
  type        = string
  default     = "vault-sp"
}

variable "key_name_prefix" {
  description = "Prefix for key name"
  type        = string
  default     = "vault-key"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}