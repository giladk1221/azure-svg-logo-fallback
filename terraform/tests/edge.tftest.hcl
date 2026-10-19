mock_provider "azurerm" {}
variables {
  name                = "svgtest000001"
  resource_group_name = "demo"
  location            = "westeurope"
  apim_id             = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/demo/providers/Microsoft.ApiManagement/service/demo"
  apim_hostname       = "demo.azure-api.net"
  tags                = {}
}
run "query_isolated_cache_and_private_origin" {
  command = plan
  module { source = "./modules/front-door" }
  assert {
    condition     = azurerm_cdn_frontdoor_route.demo.cache[0].query_string_caching_behavior == "UseQueryString"
    error_message = "explicit=true must have a distinct cache key."
  }
  assert {
    condition     = azurerm_cdn_frontdoor_origin.demo.private_link[0].private_link_target_id == var.apim_id && azurerm_cdn_frontdoor_origin.demo.private_link[0].target_type == "Gateway"
    error_message = "Front Door must use APIM's private Gateway endpoint."
  }
  assert {
    condition     = azurerm_cdn_frontdoor_firewall_policy.demo.mode == "Prevention" && azurerm_cdn_frontdoor_origin.demo.certificate_name_check_enabled
    error_message = "WAF prevention and origin certificate validation must be enabled."
  }
}
