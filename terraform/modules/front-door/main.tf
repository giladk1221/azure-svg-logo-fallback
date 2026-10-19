variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "create_profile" { type = bool }
variable "existing_front_door" {
  type    = object({ profile_name = string, resource_group_name = string, endpoint_name = string })
  default = null
}
variable "function_id" { type = string }
variable "function_hostname" { type = string }
variable "webapp" {
  type    = object({ id = string, hostname = string })
  default = null
}
data "azurerm_cdn_frontdoor_profile" "existing" {
  count               = var.create_profile ? 0 : 1
  name                = var.existing_front_door.profile_name
  resource_group_name = var.existing_front_door.resource_group_name
  lifecycle {
    postcondition {
      condition     = self.sku_name == "Premium_AzureFrontDoor"
      error_message = "Private origins require Front Door Premium."
    }
  }
}
data "azurerm_cdn_frontdoor_endpoint" "existing" {
  count               = var.create_profile ? 0 : 1
  name                = var.existing_front_door.endpoint_name
  profile_name        = var.existing_front_door.profile_name
  resource_group_name = var.existing_front_door.resource_group_name
}
locals {
  profile_id  = var.create_profile ? azurerm_cdn_frontdoor_profile.demo[0].id : data.azurerm_cdn_frontdoor_profile.existing[0].id
  endpoint_id = var.create_profile ? azurerm_cdn_frontdoor_endpoint.demo[0].id : data.azurerm_cdn_frontdoor_endpoint.existing[0].id
  hostname    = var.create_profile ? azurerm_cdn_frontdoor_endpoint.demo[0].host_name : data.azurerm_cdn_frontdoor_endpoint.existing[0].host_name
  origins     = merge({ logos = { id = var.function_id, hostname = var.function_hostname, health = "/logos/health", patterns = ["/logos/*", "/static/v2/static/logos/*"] } }, var.webapp == null ? {} : { webapp = { id = var.webapp.id, hostname = var.webapp.hostname, health = "/health", patterns = ["/*"] } })
}
resource "azurerm_cdn_frontdoor_profile" "demo" {
  count               = var.create_profile ? 1 : 0
  name                = "${var.name}-afd"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}
resource "azurerm_cdn_frontdoor_endpoint" "demo" {
  count                    = var.create_profile ? 1 : 0
  name                     = "${var.name}-edge"
  cdn_frontdoor_profile_id = local.profile_id
  tags                     = var.tags
}
resource "azurerm_cdn_frontdoor_origin_group" "demo" {
  for_each                 = local.origins
  name                     = "${var.name}-${each.key}"
  cdn_frontdoor_profile_id = local.profile_id
  session_affinity_enabled = false
  load_balancing {}
  health_probe {
    interval_in_seconds = 60
    path                = each.value.health
    protocol            = "Https"
    request_type        = "HEAD"
  }
}
resource "azurerm_cdn_frontdoor_origin" "demo" {
  for_each                       = local.origins
  name                           = each.key
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.demo[each.key].id
  enabled                        = true
  certificate_name_check_enabled = true
  host_name                      = each.value.hostname
  origin_host_header             = each.value.hostname
  http_port                      = 80
  https_port                     = 443
  private_link {
    request_message        = "svg-logo-${var.name}-${each.key}"
    location               = var.location
    private_link_target_id = each.value.id
    target_type            = "sites"
  }
}
resource "azurerm_cdn_frontdoor_route" "demo" {
  for_each                      = local.origins
  name                          = "${var.name}-${each.key}"
  cdn_frontdoor_endpoint_id     = local.endpoint_id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.demo[each.key].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.demo[each.key].id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = each.value.patterns
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
  dynamic "cache" {
    for_each = each.key == "logos" ? [1] : []
    content {
      query_string_caching_behavior = "UseQueryString"
      compression_enabled           = true
      content_types_to_compress     = ["image/svg+xml", "text/html"]
    }
  }
}
resource "azurerm_cdn_frontdoor_firewall_policy" "demo" {
  count               = var.create_profile ? 1 : 0
  name                = "${var.name}waf"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  enabled             = true
  mode                = "Prevention"
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }
  tags = var.tags
}
resource "azurerm_cdn_frontdoor_security_policy" "demo" {
  count                    = var.create_profile ? 1 : 0
  name                     = "logo-waf"
  cdn_frontdoor_profile_id = local.profile_id
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.demo[0].id
      association {
        domain { cdn_frontdoor_domain_id = local.endpoint_id }
        patterns_to_match = ["/*"]
      }
    }
  }
}
output "hostname" { value = local.hostname }
output "approvals" { value = [for k, v in local.origins : { resource_id = v.id, request_message = "svg-logo-${var.name}-${k}" }] }
