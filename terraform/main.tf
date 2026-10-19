resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
locals {
  name         = "${var.name_prefix}${random_string.suffix.result}"
  function_zip = abspath(var.package_path)
  package_name = "logo-${filesha256(local.function_zip)}.zip"
}
resource "terraform_data" "guardrails" {
  lifecycle {
    precondition {
      condition     = var.mode != "existing_front_door" || var.existing_front_door != null
      error_message = "Provide the existing Premium Front Door profile and endpoint."
    }
    precondition {
      condition     = !var.publish_artifacts || startswith(var.publisher_ssh_public_key, "ssh-")
      error_message = "Set publisher_ssh_public_key, or use your own private runner."
    }
    precondition {
      condition     = !var.publish_artifacts || var.existing_network == null || try(var.existing_network.publisher_subnet_id != null, false)
      error_message = "An existing network requires a publisher subnet with outbound connectivity, or publish_artifacts=false."
    }
  }
}
resource "azurerm_resource_group" "demo" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = var.tags
}
module "network" {
  source               = "./modules/private-network"
  name                 = local.name
  resource_group_name  = azurerm_resource_group.demo.name
  location             = var.location
  create_network       = var.existing_network == null
  existing_network     = var.existing_network
  private_dns_zone_ids = var.private_dns_zone_ids
  tags                 = var.tags
}
module "function" {
  source                     = "./modules/logo-function"
  name                       = local.name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.demo.name
  integration_subnet_id      = module.network.function_subnet_id
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  private_dns_zone_ids       = module.network.private_dns_zone_ids
  existing_service_plan_id   = var.existing_service_plan_id
  plan_sku                   = var.function_plan_sku
  existing_catalog           = var.existing_catalog
  package_name               = local.package_name
  tags                       = var.tags
  depends_on                 = [terraform_data.guardrails]
}
module "webapp" {
  count               = var.mode == "full" ? 1 : 0
  source              = "./modules/webapp"
  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.demo.name
  service_plan_id     = module.function.service_plan_id
  tags                = var.tags
}
module "front_door" {
  count               = var.mode != "function_only" ? 1 : 0
  source              = "./modules/front-door"
  name                = local.name
  resource_group_name = azurerm_resource_group.demo.name
  create_profile      = var.mode == "full"
  existing_front_door = var.existing_front_door
  function_id         = module.function.id
  function_hostname   = module.function.hostname
  webapp              = var.mode == "full" ? { id = module.webapp[0].id, hostname = module.webapp[0].hostname } : null
  location            = var.location
  tags                = var.tags
}
module "publisher" {
  count                = var.publish_artifacts ? 1 : 0
  source               = "./modules/private-publisher"
  name                 = local.name
  location             = var.location
  resource_group_name  = azurerm_resource_group.demo.name
  subnet_id            = module.network.publisher_subnet_id
  create_outbound_nat  = var.existing_network == null
  ssh_public_key       = var.publisher_ssh_public_key
  host_storage_id      = module.function.host_storage_id
  host_storage_name    = module.function.host_storage_name
  catalog_storage_id   = module.function.catalog_storage_id
  catalog_storage_name = module.function.catalog_storage_name
  seed_catalog         = var.existing_catalog == null
  package_name         = local.package_name
  package_path         = local.function_zip
  assets_path          = "${path.module}/../assets/logos"
  tags                 = var.tags
  depends_on           = [module.function]
}

# Run-from-package URLs require a restart and trigger synchronization after publishing.
resource "terraform_data" "package_version" {
  input = local.package_name
}

resource "azapi_resource_action" "restart" {
  count       = var.publish_artifacts ? 1 : 0
  type        = "Microsoft.Web/sites@2024-04-01"
  resource_id = module.function.id
  action      = "restart"
  method      = "POST"
  depends_on  = [module.publisher]
  lifecycle {
    replace_triggered_by = [terraform_data.package_version]
  }
}

resource "azapi_resource_action" "sync" {
  count       = var.publish_artifacts ? 1 : 0
  type        = "Microsoft.Web/sites@2024-04-01"
  resource_id = module.function.id
  action      = "syncfunctiontriggers"
  method      = "POST"
  retry = {
    interval_seconds     = 15
    max_interval_seconds = 60
    error_message_regex  = [".*"]
  }

  depends_on = [azapi_resource_action.restart]
  lifecycle {
    replace_triggered_by = [terraform_data.package_version]
  }
}
