mock_provider "azurerm" {
  mock_data "azurerm_cdn_frontdoor_profile" {
    defaults = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Cdn/profiles/existing", sku_name = "Premium_AzureFrontDoor" }
  }
  mock_data "azurerm_cdn_frontdoor_endpoint" {
    defaults = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Cdn/profiles/existing/afdEndpoints/edge", host_name = "edge.azurefd.net" }
  }
}
variables {
  subscription_id   = "22222222-2222-2222-2222-222222222222"
  name              = "testedge"
  function_id       = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/origins/providers/Microsoft.Web/sites/function"
  function_hostname = "function.azurewebsites.net"
}
run "function_origin_only" {
  command = plan
  assert {
    condition     = length(azurerm_resource_group.edge) == 1 && length(output.front_door_private_link_approvals) == 1 && output.front_door_private_link_approvals[0].resource_id == var.function_id && output.webapp_url == null
    error_message = "Edge must connect the supplied Function without requiring a website."
  }
}
run "add_website_to_existing_edge" {
  command = plan
  variables {
    existing_front_door = { profile_name = "existing", resource_group_name = "shared", endpoint_name = "edge" }
    webapp              = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/origins/providers/Microsoft.Web/sites/webapp", hostname = "webapp.azurewebsites.net" }
  }
  assert {
    condition     = length(azurerm_resource_group.edge) == 0 && length(output.front_door_private_link_approvals) == 2 && output.demo_url == "https://edge.azurefd.net/logos/demo" && output.webapp_url == "https://edge.azurefd.net/"
    error_message = "Adding the website must preserve the Function origin and use the existing edge."
  }
}
