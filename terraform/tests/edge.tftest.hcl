mock_provider "azurerm" {
  mock_data "azurerm_cdn_frontdoor_profile" {
    defaults = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Cdn/profiles/existing", sku_name = "Premium_AzureFrontDoor" }
  }
  mock_data "azurerm_cdn_frontdoor_endpoint" {
    defaults = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Cdn/profiles/existing/afdEndpoints/edge", host_name = "edge.azurefd.net" }
  }
}
variables {
  name                = "svgtest000001"
  resource_group_name = "demo"
  location            = "westeurope"
  create_profile      = true
  function_id         = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/demo/providers/Microsoft.Web/sites/function"
  function_hostname   = "function.azurewebsites.net"
  webapp              = { id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/demo/providers/Microsoft.Web/sites/webapp", hostname = "webapp.azurewebsites.net" }
  tags                = {}
}
run "private_origins_and_cache" {
  command = plan
  module { source = "./modules/front-door" }
  assert {
    condition     = azurerm_cdn_frontdoor_route.demo["logos"].cache[0].query_string_caching_behavior == "UseQueryString" && length(azurerm_cdn_frontdoor_route.demo["webapp"].cache) == 0
    error_message = "Logo query keys must be isolated; Web App route must not cache."
  }
  assert {
    condition     = alltrue([for o in azurerm_cdn_frontdoor_origin.demo : o.private_link[0].target_type == "sites" && o.certificate_name_check_enabled])
    error_message = "Both apps must use private sites origins with certificate validation."
  }
  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.demo[0].mode == "Prevention"
    error_message = "New profile must have WAF prevention."
  }
}
run "existing_parents_stay_external" {
  command = plan
  module { source = "./modules/front-door" }
  variables {
    create_profile      = false
    webapp              = null
    existing_front_door = { profile_name = "existing", resource_group_name = "shared", endpoint_name = "edge" }
  }
  assert {
    condition     = length(azurerm_cdn_frontdoor_profile.demo) == 0 && length(azurerm_cdn_frontdoor_endpoint.demo) == 0 && length(azurerm_cdn_frontdoor_firewall_policy.demo) == 0 && length(azurerm_cdn_frontdoor_route.demo) == 1
    error_message = "Existing profile, endpoint, WAF and default Web App routes must not be recreated."
  }
}
