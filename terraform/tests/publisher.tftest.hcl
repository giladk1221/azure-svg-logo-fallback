mock_provider "azurerm" {}
mock_provider "azapi" {}
variables {
  name                 = "svgtest000001"
  resource_group_name  = "demo"
  location             = "westeurope"
  subnet_id            = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/demo/providers/Microsoft.Network/virtualNetworks/demo/subnets/publisher"
  create_outbound_nat  = true
  ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB"
  host_storage_id      = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/demo/providers/Microsoft.Storage/storageAccounts/demohost"
  host_storage_name    = "demohost"
  catalog_storage_id   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/demo/providers/Microsoft.Storage/storageAccounts/demologos"
  catalog_storage_name = "demologos"
  seed_catalog         = true
  package_name         = "demo.zip"
  package_path         = "../.build/function.zip"
  assets_path          = "../assets/logos"
  tags                 = {}
}
run "private_publisher_has_scoped_permissions_and_reports_failures" {
  command = plan
  module { source = "./modules/private-publisher" }
  assert {
    condition     = azurerm_network_interface.publisher.ip_configuration[0].public_ip_address_id == null && azurerm_linux_virtual_machine.publisher.disable_password_authentication
    error_message = "Publisher must have no public NIC address or password login."
  }
  assert {
    condition     = azapi_resource.upload.body.properties.treatFailureAsDeploymentFailure && !azapi_resource.upload.body.properties.asyncExecution
    error_message = "Failed uploads must fail Terraform rather than report false success."
  }
  assert {
    condition     = azurerm_role_assignment.upload["packages"].scope == "${var.host_storage_id}/blobServices/default/containers/packages" && azurerm_role_assignment.upload["logos"].scope == "${var.catalog_storage_id}/blobServices/default/containers/logos"
    error_message = "Publisher write access must be container-scoped."
  }
}
run "reused_catalog_is_not_seeded" {
  command = plan
  module { source = "./modules/private-publisher" }
  variables { seed_catalog = false }
  assert {
    condition     = length(azurerm_role_assignment.upload) == 1 && length(jsondecode(base64decode(local.payload)).assets) == 0
    error_message = "Existing catalog must receive no publisher write role or sample uploads."
  }
}
