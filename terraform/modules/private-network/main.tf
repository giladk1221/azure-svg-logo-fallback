variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "create_network" {
  type = bool
}

variable "existing_network" {
  type    = any
  default = null
}

variable "private_dns_zone_ids" {
  type = map(string)
}

variable "tags" {
  type = map(string)
}

locals {
  zones = {
    blob = "privatelink.blob.core.windows.net",

  }

  create_zones = {
    for k, v in local.zones :
    k => v if !contains(keys(var.private_dns_zone_ids), k)
  }

  vnet_id = var.create_network ? azurerm_virtual_network.demo[0].id : var.existing_network.vnet_id
  subnets = { function = "10.84.1.0/24", endpoints = "10.84.2.0/24", publisher = "10.84.3.0/27" }
}

resource "azurerm_virtual_network" "demo" {
  count               = var.create_network ? 1 : 0
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.84.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "demo" {
  for_each = var.create_network ? local.subnets : {
  }

  name                              = each.key
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.demo[0].name
  address_prefixes                  = [each.value]
  private_endpoint_network_policies = "Disabled"
  default_outbound_access_enabled   = false
  dynamic "delegation" {
    for_each = each.key == "function" ? [1] : []
    content {
      name = "web"
      service_delegation {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

resource "azurerm_private_dns_zone" "demo" {
  for_each            = local.create_zones
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "demo" {
  for_each              = local.create_zones
  name                  = "${var.name}-${each.key}"
  private_dns_zone_name = azurerm_private_dns_zone.demo[each.key].name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
}

output "function_subnet_id" {
  value = var.create_network ? azurerm_subnet.demo["function"].id : var.existing_network.function_subnet_id
}

output "private_endpoint_subnet_id" {
  value = var.create_network ? azurerm_subnet.demo["endpoints"].id : var.existing_network.private_endpoint_subnet_id
}

output "publisher_subnet_id" {
  value = var.create_network ? azurerm_subnet.demo["publisher"].id : try(var.existing_network.publisher_subnet_id, null)
}

output "private_dns_zone_ids" {
  value = merge(var.private_dns_zone_ids, {
    for k, v in azurerm_private_dns_zone.demo :
    k => v.id
    }
  )
  depends_on = [azurerm_private_dns_zone_virtual_network_link.demo]
}
