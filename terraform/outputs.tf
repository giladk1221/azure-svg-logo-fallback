output "resource_group_name" { value = azurerm_resource_group.demo.name }
output "function_name" { value = module.function.name }
output "function_id" { value = module.function.id }
output "function_hostname" { value = module.function.hostname }
output "host_storage_name" { value = module.function.host_storage_name }
output "catalog_storage_name" { value = module.function.catalog_storage_name }
output "package_name" { value = local.package_name }
output "demo_url" { value = var.mode == "function_only" ? null : "https://${module.front_door[0].hostname}/logos/demo" }
output "webapp_url" { value = var.mode == "full" ? "https://${module.front_door[0].hostname}/" : null }
output "front_door_private_link_approvals" { value = var.mode == "function_only" ? [] : module.front_door[0].approvals }
output "private_publisher_enabled" { value = var.publish_artifacts }
