output "resource_group_name" {
  value = azurerm_resource_group.demo.name
}

output "function_name" {
  value = module.function.name
}

output "function_hostname" {
  value = module.function.hostname
}

output "backend_audience" {
  value = module.function.backend_audience
}

output "host_storage_name" {
  value = module.function.host_storage_name
}

output "catalog_storage_name" {
  value = module.function.catalog_storage_name
}

output "package_name" {
  value = local.package_name
}

output "api_gateway_url" {
  value = local.apim_gateway
}

output "demo_url" {
  value = var.enable_front_door ? "https://${module.front_door[0].hostname}/logos/demo" : (local.has_apim ? "${local.apim_gateway}/logos/demo" : null)
}

output "front_door_private_link_approval" {
  value = var.enable_front_door ? {
    apim_id         = local.apim_id,
    request_message = module.front_door[0].request_message,
    profile_id      = module.front_door[0].id
  } : null
}

output "private_publisher_enabled" {
  value = var.publish_artifacts
}
