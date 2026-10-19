resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  name         = "${var.name_prefix}${random_string.suffix.result}"
  has_apim     = var.mode != "function_only"
  function_zip = abspath(var.package_path)
  package_name = "logo-${filesha256(local.function_zip)}.zip"
  apim_id      = var.mode == "full" ? azurerm_api_management.demo[0].id : (var.mode == "existing_apim" ? data.azurerm_api_management.existing[0].id : null)
  apim_name    = var.mode == "full" ? azurerm_api_management.demo[0].name : try(var.existing_apim.name, null)
  apim_rg      = var.mode == "full" ? azurerm_resource_group.demo.name : try(var.existing_apim.resource_group_name, null)
  apim_gateway = var.mode == "full" ? azurerm_api_management.demo[0].gateway_url : (var.mode == "existing_apim" ? data.azurerm_api_management.existing[0].gateway_url : null)
  callers      = var.mode == "full" ? [azurerm_api_management.demo[0].identity[0].principal_id] : (var.mode == "existing_apim" ? try([data.azurerm_api_management.existing[0].identity[0].principal_id], []) : var.allowed_caller_principal_ids)
}

resource "terraform_data" "guardrails" {
  lifecycle {
    precondition {
      condition     = var.mode != "full" || var.existing_network == null
      error_message = "Full mode creates its own VNet; use existing_apim or function_only to reuse a network."
    }

    precondition {
      condition     = !var.lock_apim_public_access || (var.mode == "full" && var.enable_front_door)
      error_message = "Lockdown requires full mode with Front Door."
    }

    precondition {
      condition     = var.mode != "full" || var.publisher_email != ""
      error_message = "Set publisher_email for a new APIM instance."
    }

    precondition {
      condition     = var.mode != "existing_apim" || (var.existing_apim != null && var.existing_network != null)
      error_message = "existing_apim requires existing_apim and existing_network inputs."
    }

    precondition {
      condition     = !var.enable_front_door || var.mode == "full"
      error_message = "The optional Front Door module is included only in full mode; shared gateways retain their existing ingress configuration."
    }

    precondition {
      condition     = var.mode != "function_only" || length(var.allowed_caller_principal_ids) > 0
      error_message = "function_only requires at least one allowed managed identity object ID."
    }

    precondition {
      condition     = !var.publish_artifacts || startswith(var.publisher_ssh_public_key, "ssh-")
      error_message = "Set publisher_ssh_public_key to a PUBLIC SSH key, or publish from your own private runner."
    }

    precondition {
      condition     = !var.publish_artifacts || var.existing_network == null || try(var.existing_network.publisher_subnet_id != null, false)
      error_message = "Provide a dedicated publisher subnet with outbound Azure connectivity, or disable the optional publisher."
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
  create_apim_subnet   = var.mode == "full"
  tags                 = var.tags
}

data "azurerm_api_management" "existing" {
  count               = var.mode == "existing_apim" ? 1 : 0
  name                = var.existing_apim.name
  resource_group_name = var.existing_apim.resource_group_name
  lifecycle {
    postcondition {
      condition     = try(self.identity[0].principal_id != "", false)
      error_message = "Existing APIM needs a system-assigned managed identity."
    }
  }
}

resource "azurerm_api_management" "demo" {
  count                         = var.mode == "full" ? 1 : 0
  name                          = "${local.name}-apim"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.demo.name
  publisher_name                = var.publisher_name
  publisher_email               = var.publisher_email
  sku_name                      = "StandardV2_1"
  public_network_access_enabled = !var.lock_apim_public_access
  virtual_network_type          = "External"
  virtual_network_configuration {
    subnet_id = module.network.apim_subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  tags       = var.tags
  depends_on = [terraform_data.guardrails]
}

module "function" {
  source                        = "./modules/logo-function"
  name                          = local.name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.demo.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  integration_subnet_id         = module.network.function_subnet_id
  private_endpoint_subnet_id    = module.network.private_endpoint_subnet_id
  private_dns_zone_ids          = module.network.private_dns_zone_ids
  existing_service_plan_id      = var.existing_service_plan_id
  plan_sku                      = var.function_plan_sku
  existing_catalog              = var.existing_catalog
  backend_application_client_id = var.backend_application_client_id
  allowed_caller_principal_ids  = local.callers
  package_name                  = local.package_name
  tags                          = var.tags
  depends_on                    = [terraform_data.guardrails]
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

module "api" {
  count               = local.has_apim ? 1 : 0
  source              = "./modules/apim-logo-api"
  api_management_name = local.apim_name
  resource_group_name = local.apim_rg
  name                = "${var.name_prefix}-logos"
  function_hostname   = module.function.hostname
  backend_audience    = module.function.backend_audience
  front_door_id       = var.enable_front_door ? module.front_door[0].resource_guid : null
  depends_on          = [module.publisher]
}

module "front_door" {
  count               = var.enable_front_door ? 1 : 0
  source              = "./modules/front-door"
  name                = local.name
  resource_group_name = azurerm_resource_group.demo.name
  apim_id             = local.apim_id
  apim_hostname       = replace(local.apim_gateway, "https://", "")
  location            = var.location
  tags                = var.tags
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

data "azapi_resource" "existing_apim_network" {
  count                  = var.mode == "existing_apim" ? 1 : 0
  type                   = "Microsoft.ApiManagement/service@2024-05-01"
  resource_id            = data.azurerm_api_management.existing[0].id
  response_export_values = ["properties.virtualNetworkType"]
  lifecycle {
    postcondition {
      condition     = contains(["External", "Internal"], try(self.output.properties.virtualNetworkType, ""))
      error_message = "Existing APIM needs private outbound networking in its owning stack first."
    }
  }
}
