mock_provider "azurerm" {
  mock_data "azurerm_cdn_frontdoor_profile" {
    defaults = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Cdn/profiles/existing", sku_name = "Premium_AzureFrontDoor" }
  }
  mock_data "azurerm_cdn_frontdoor_endpoint" {
    defaults = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Cdn/profiles/existing/afdEndpoints/edge", host_name = "edge.azurefd.net" }
  }
}
mock_provider "azapi" {}
mock_provider "random" {}
variables {
  subscription_id   = "22222222-2222-2222-2222-222222222222"
  publish_artifacts = false
}
run "full_demo" {
  command = plan
  variables { mode = "full" }
  assert {
    condition     = length(module.webapp) == 1 && length(module.front_door) == 1
    error_message = "Full mode must include Web App and Front Door."
  }
}
run "existing_front_door" {
  command = plan
  variables {
    mode                = "existing_front_door"
    existing_front_door = { profile_name = "existing", resource_group_name = "shared", endpoint_name = "edge" }
  }
  assert {
    condition     = length(module.webapp) == 0 && length(module.front_door) == 1 && output.demo_url == "https://edge.azurefd.net/logos/demo"
    error_message = "Existing mode must use the selected endpoint without creating a Web App."
  }
}
run "function_only" {
  command = plan
  variables { mode = "function_only" }
  assert {
    condition     = length(module.webapp) == 0 && length(module.front_door) == 0 && output.demo_url == null
    error_message = "Function-only must not create a public endpoint or Web App."
  }
}
