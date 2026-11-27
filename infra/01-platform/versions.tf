terraform {
  required_version = ">= 1.9"

  # Remote state in the storage account created by scripts/bootstrap.sh.
  # Values come from -backend-config in the pipeline. Entra ID auth only, no storage keys.
  backend "azurerm" {
    use_azuread_auth = true
    key              = "platform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4"
    }
  }
}

provider "azurerm" {
  features {}
  # The pipeline identity only has rights in a few resource groups, so it can't register providers.
  resource_provider_registrations = "none"
}

provider "azuread" {}
