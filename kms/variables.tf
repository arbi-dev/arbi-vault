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

variable "cloud_provider" {
  description = "Cloud provider (azure, aws, gcp)"
  type        = string
  default     = "azure"
  
  validation {
    condition     = contains(["azure", "aws", "gcp"], var.cloud_provider)
    error_message = "Cloud provider must be one of: azure, aws, gcp."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "uksouth"
}

variable "use_existing_shared_resources" {
  description = "Whether to use existing shared resources (resource group, key vault)"
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "arbi-vault-shared-rg"
}

variable "key_vault_name" {
  description = "Name of the key vault"
  type        = string
  default     = "arbi-vault-shared-kv"
}