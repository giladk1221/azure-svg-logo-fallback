variable "api_management_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "name" {
  type = string
}

variable "function_hostname" {
  type = string
}

variable "backend_audience" {
  type = string
}

variable "front_door_id" {
  type    = string
  default = null
}

locals {
  paths = {
    logos  = "logos",
    legacy = "static/v2/static/logos"
  }
}

resource "azurerm_api_management_api" "logos" {
  for_each              = local.paths
  name                  = "${var.name}-${each.key}"
  resource_group_name   = var.resource_group_name
  api_management_name   = var.api_management_name
  revision              = "1"
  display_name          = "SVG logo ${each.key}"
  path                  = each.value
  protocols             = ["https"]
  service_url           = "https://${var.function_hostname}"
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "logos" {
  for_each = {
    for pair in setproduct(keys(local.paths), ["GET", "HEAD"]) : "${pair[0]}-${lower(pair[1])}" => {
      api    = pair[0],
      method = pair[1]
    }
  }

  operation_id        = lower(each.value.method)
  api_name            = azurerm_api_management_api.logos[each.value.api].name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  display_name        = "${each.value.method} SVG lookup, fallback, demo or health"
  method              = each.value.method
  url_template        = "/*"
  response {
    status_code = 200
    description = "Original or generated SVG; demo/health use their respective content types."
  }

  response {
    status_code = 404
    description = "Missing logo with explicit=true, or unsupported path."
  }

  response {
    status_code = 502
    description = "Origin failure; never cached as a generated logo."
  }
}

resource "azurerm_api_management_api_policy" "logos" {
  for_each            = local.paths
  api_name            = azurerm_api_management_api.logos[each.key].name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content = templatefile("${path.module}/policy.xml.tftpl", {
    function_hostname = var.function_hostname,
    audience          = var.backend_audience,
    front_door_id     = var.front_door_id
    }
  )
}
