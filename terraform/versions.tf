terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi   = { source = "Azure/azapi", version = "~> 2.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {
    resource_group { prevent_deletion_if_contains_resources = true }
  }
}
provider "azapi" { subscription_id = var.subscription_id }
