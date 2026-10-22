# Independent state: connects existing origins; never provisions or owns them.
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
  description = "Supported Front Door Private Link region near the origins."
  type        = string
  default     = "westeurope"
}
variable "function_id" { type = string }
variable "function_hostname" { type = string }
variable "webapp" {
  description = "Optional existing website origin; use the standalone webapp outputs."
  type        = object({ id = string, hostname = string })
  default     = null
}
variable "existing_front_door" {
  description = "Omit to create a new Premium profile, endpoint and WAF."
  type        = object({ profile_name = string, resource_group_name = string, endpoint_name = string })
  default     = null
}
variable "tags" {
  type    = map(string)
  default = { purpose = "svg-logo-demo-edge" }
}
resource "azurerm_resource_group" "edge" {
  count    = var.existing_front_door == null ? 1 : 0
  name     = "rg-${var.name}-edge"
  location = var.location
  tags     = var.tags
}
module "front_door" {
  source              = "../../modules/front-door"
  name                = var.name
  resource_group_name = var.existing_front_door == null ? azurerm_resource_group.edge[0].name : var.existing_front_door.resource_group_name
  location            = var.location
  create_profile      = var.existing_front_door == null
  existing_front_door = var.existing_front_door
  function_id         = var.function_id
  function_hostname   = var.function_hostname
  webapp              = var.webapp
  tags                = var.tags
}
output "demo_url" { value = "https://${module.front_door.hostname}/logos/demo" }
output "webapp_url" { value = var.webapp == null ? null : "https://${module.front_door.hostname}/" }
output "front_door_private_link_approvals" { value = module.front_door.approvals }
