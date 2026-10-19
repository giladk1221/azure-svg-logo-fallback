mock_provider "azurerm" {}
run "private_webapp" {
  command = plan
  module { source = "./modules/webapp" }
  variables {
    name                = "svgtest000001"
    location            = "westeurope"
    resource_group_name = "demo"
    service_plan_id     = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/demo/providers/Microsoft.Web/serverFarms/demo"
    tags                = {}
  }
  assert {
    condition     = !azurerm_linux_web_app.demo.public_network_access_enabled && azurerm_linux_web_app.demo.https_only && !azurerm_linux_web_app.demo.webdeploy_publish_basic_authentication_enabled
    error_message = "Web App must remain private, HTTPS-only and disable basic publishing."
  }
}
