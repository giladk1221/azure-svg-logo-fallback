variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "apim_id" {
  type = string
}

variable "apim_hostname" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  request_message = "svg-logo-${var.name}"
}

resource "azurerm_cdn_frontdoor_profile" "demo" {
  name                = "${var.name}-afd"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "demo" {
  name                     = "${var.name}-edge"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.demo.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "demo" {
  name                     = "logo-api"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.demo.id
  session_affinity_enabled = false
  load_balancing {
  }

  health_probe {
    interval_in_seconds = 60
    path                = "/logos/health"
    protocol            = "Https"
    request_type        = "HEAD"
  }
}

resource "azurerm_cdn_frontdoor_origin" "demo" {
  name                           = "apim"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.demo.id
  enabled                        = true
  certificate_name_check_enabled = true
  host_name                      = var.apim_hostname
  origin_host_header             = var.apim_hostname
  http_port                      = 80
  https_port                     = 443
  private_link {
    request_message        = local.request_message
    location               = var.location
    private_link_target_id = var.apim_id
    target_type            = "Gateway"
  }
}

resource "azurerm_cdn_frontdoor_route" "demo" {
  name                          = "logos"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.demo.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.demo.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.demo.id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/logos/*", "/static/v2/static/logos/*"]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
  cache {
    query_string_caching_behavior = "UseQueryString"
    compression_enabled           = true
    content_types_to_compress     = ["image/svg+xml", "text/html"]
  }
}

resource "azurerm_cdn_frontdoor_firewall_policy" "demo" {
  name                = "${var.name}waf"
  resource_group_name = var.resource_group_name
  sku_name            = azurerm_cdn_frontdoor_profile.demo.sku_name
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
  name                     = "logo-waf"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.demo.id
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.demo.id
      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.demo.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

output "hostname" {
  value = azurerm_cdn_frontdoor_endpoint.demo.host_name
}

output "resource_guid" {
  value = azurerm_cdn_frontdoor_profile.demo.resource_guid
}

output "id" {
  value = azurerm_cdn_frontdoor_profile.demo.id
}

output "request_message" {
  value = local.request_message
}
