# Independent state: only the sample website and its plan (unless reused).
terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
provider "azurerm" {
  subscription_id = var.subscription_id
  features {
    resource_group { prevent_deletion_if_contains_resources = true }
  }
}
variable "subscription_id" { type = string }
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,17}$", var.name))
    error_message = "Use a globally unique name: 3–18 lowercase letters/digits, starting with a letter."
  }
}
variable "location" {
  type    = string
  default = "westeurope"
}
variable "existing_service_plan_id" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = { purpose = "svg-logo-demo-webapp" }
}
resource "azurerm_resource_group" "webapp" {
  name     = "rg-${var.name}-webapp"
  location = var.location
  tags     = var.tags
}
resource "azurerm_service_plan" "webapp" {
  count               = var.existing_service_plan_id == null ? 1 : 0
  name                = "${var.name}-webapp-plan"
  resource_group_name = azurerm_resource_group.webapp.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}
module "webapp" {
  source              = "../../modules/webapp"
  name                = var.name
  location            = var.location
  resource_group_name = azurerm_resource_group.webapp.name
  service_plan_id     = var.existing_service_plan_id == null ? azurerm_service_plan.webapp[0].id : var.existing_service_plan_id
  tags                = var.tags
}
output "webapp_id" { value = module.webapp.id }
output "webapp_hostname" { value = module.webapp.hostname }
output "resource_group_name" { value = azurerm_resource_group.webapp.name }
