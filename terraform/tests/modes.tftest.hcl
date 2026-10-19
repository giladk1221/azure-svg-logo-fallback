mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_data "azurerm_api_management" {
    defaults = {
      id          = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.ApiManagement/service/shared-api"
      name        = "shared-api"
      gateway_url = "https://shared-api.azure-api.net"
      identity    = [{ type = "SystemAssigned", principal_id = "33333333-3333-3333-3333-333333333333", tenant_id = "11111111-1111-1111-1111-111111111111", identity_ids = [] }]
    }
  }
}
mock_provider "azuread" {}
mock_provider "random" {}
mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = { output = { properties = { virtualNetworkType = "External" } } }
  }
}
variables {
  subscription_id   = "22222222-2222-2222-2222-222222222222"
  publisher_email   = "demo@example.com"
  publish_artifacts = false
}
run "full_private_backend" {
  command = plan
  variables { mode = "full" }
  assert {
    condition     = length(azurerm_api_management.demo) == 1 && azurerm_api_management.demo[0].sku_name == "StandardV2_1"
    error_message = "Full mode must create Standard v2 APIM."
  }
  assert {
    condition     = length(module.api) == 1 && length(module.publisher) == 0
    error_message = "Full mode must include API routing and honor publisher opt-out."
  }
}
run "existing_apim_integration" {
  command = plan
  variables {
    mode          = "existing_apim"
    existing_apim = { name = "shared-api", resource_group_name = "shared" }
    existing_network = {
      vnet_id                    = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Network/virtualNetworks/shared"
      function_subnet_id         = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Network/virtualNetworks/shared/subnets/functions"
      private_endpoint_subnet_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Network/virtualNetworks/shared/subnets/endpoints"
    }
  }
  assert {
    condition     = length(azurerm_api_management.demo) == 0 && length(module.api) == 1 && length(module.front_door) == 0
    error_message = "Existing mode must add APIs without recreating APIM or Front Door."
  }
  assert {
    condition     = local.callers == tolist(["33333333-3333-3333-3333-333333333333"])
    error_message = "The existing APIM system identity must be the authorized caller."
  }
}
run "function_only" {
  command = plan
  variables {
    mode                         = "function_only"
    allowed_caller_principal_ids = ["33333333-3333-3333-3333-333333333333"]
  }
  assert {
    condition     = length(azurerm_api_management.demo) == 0 && length(module.api) == 0 && length(module.front_door) == 0
    error_message = "Function-only must create no gateway or APIs."
  }
  assert {
    condition     = output.demo_url == null
    error_message = "A private Function-only deployment must not advertise a public demo URL."
  }
}
run "full_front_door" {
  command = plan
  variables { enable_front_door = true }
  assert {
    condition     = length(module.front_door) == 1
    error_message = "Requested Front Door must be included."
  }
}
