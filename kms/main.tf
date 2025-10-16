terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azuread" {}

module "azure_kms" {
  source = "./modules/azure"
  
  deployment_domain = var.deployment_domain
  environment      = var.environment
  location         = var.location
  
  use_existing_shared_resources = var.use_existing_shared_resources
  resource_group_name          = var.resource_group_name
  key_vault_name              = var.key_vault_name
  
  tags = {
    Project     = "arbi-vault"
    Environment = var.environment
    ManagedBy   = "terraform"
    CreatedBy   = "create-kms-script"
  }
}