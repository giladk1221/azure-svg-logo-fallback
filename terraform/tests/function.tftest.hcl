mock_provider "azurerm" {}
mock_provider "azapi" {}
variables {
  name                       = "svgtest000001"
  resource_group_name        = "demo"
  location                   = "westeurope"
  integration_subnet_id      = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Network/virtualNetworks/shared/subnets/functions"
  private_endpoint_subnet_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Network/virtualNetworks/shared/subnets/endpoints"
  private_dns_zone_ids = {
    blob = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }
  plan_sku     = "B1"
  package_name = "test.zip"
  tags         = {}
}
run "private_function_identity_and_storage" {
  command = plan
  module { source = "./modules/logo-function" }
  assert {
    condition     = !azurerm_linux_function_app.demo.public_network_access_enabled && azurerm_linux_function_app.demo.https_only
    error_message = "Function must have public access disabled and require HTTPS."
  }

  assert {
    condition     = !azurerm_storage_account.host.shared_access_key_enabled && !azurerm_storage_account.host.public_network_access_enabled && !azurerm_storage_account.catalog[0].public_network_access_enabled
    error_message = "Both stores must remain private, with no host shared-key auth."
  }
  assert {
    condition     = azurerm_role_assignment.catalog_reader.role_definition_name == "Storage Blob Data Reader" && length(azurerm_role_assignment.host) == 1
    error_message = "Catalog permissions must be read-only and unused trigger roles must not be added."
  }
}
run "reuse_catalog_and_plan" {
  command = plan
  module { source = "./modules/logo-function" }
  variables {
    existing_service_plan_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Web/serverFarms/shared"
    existing_catalog = {
      account_id     = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Storage/storageAccounts/customerlogos"
      account_name   = "customerlogos"
      container_name = "brand-assets"
    }
  }
  assert {
    condition     = length(azurerm_storage_account.catalog) == 0 && length(azurerm_service_plan.demo) == 0 && length(azapi_resource.logos) == 0
    error_message = "Reused components must not be created or taken over."
  }
  assert {
    condition     = azurerm_role_assignment.catalog_reader.scope == "${var.existing_catalog.account_id}/blobServices/default/containers/brand-assets" && azurerm_linux_function_app.demo.app_settings["LOGO_CONTAINER"] == "brand-assets"
    error_message = "Reused catalog permissions and lookup must target the supplied container only."
  }
}
