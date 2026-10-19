mock_provider "azurerm" {}
variables {
  api_management_name = "shared-api"
  resource_group_name = "shared"
  name                = "test-logos"
  function_hostname   = "demo.azurewebsites.net"
  backend_audience    = "api://44444444-4444-4444-4444-444444444444"
}
run "gateway_preserves_query_and_uses_identity" {
  command = plan
  module { source = "./modules/apim-logo-api" }
  assert {
    condition     = strcontains(azurerm_api_management_api_policy.logos["logos"].xml_content, "copy-unmatched-params=\"true\"") && strcontains(azurerm_api_management_api_policy.logos["logos"].xml_content, "context.Request.OriginalUrl.Path")
    error_message = "Gateway must preserve the original path and explicit query value."
  }
  assert {
    condition     = strcontains(azurerm_api_management_api_policy.logos["logos"].xml_content, "authentication-managed-identity resource=\"${var.backend_audience}\"") && !strcontains(azurerm_api_management_api_policy.logos["logos"].xml_content, "cache-lookup")
    error_message = "Gateway must use its identity and must not add a response cache."
  }
}
