variable "subscription_id" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "svglogo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.name_prefix))
    error_message = "Use 3–12 lowercase letters/digits, beginning with a letter."
  }
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "mode" {
  type    = string
  default = "full"
  validation {
    condition     = contains(["full", "existing_apim", "function_only"], var.mode)
    error_message = "Use full, existing_apim, or function_only."
  }
}

variable "publisher_name" {
  type    = string
  default = "SVG demo"
}

variable "publisher_email" {
  type    = string
  default = ""
}

variable "enable_front_door" {
  type    = bool
  default = false
}

variable "existing_apim" {
  description = "Existing APIM is referenced, never imported or modified as a service. Its system identity and private outbound networking must already be configured."
  type = object({
    name                = string,
    resource_group_name = string
    }
  )
  default = null
}

variable "existing_network" {
  description = "Existing connected network and dedicated subnets. DNS links must cover the APIM VNet."
  type = object({
    vnet_id                    = string,
    function_subnet_id         = string,
    private_endpoint_subnet_id = string,
    publisher_subnet_id        = optional(string)
    }
  )
  default = null
}

variable "private_dns_zone_ids" {
  description = "Reuse existing zone IDs; omitted zones are created and linked to the chosen VNet. Avoid duplicate zones in a shared network."
  type        = map(string)
  default = {
  }
}

variable "existing_service_plan_id" {
  type    = string
  default = null
}

variable "function_plan_sku" {
  type    = string
  default = "B1"
}

variable "existing_catalog" {
  description = "Optional existing logo catalog. Private Blob connectivity/DNS must already work; this stack adds only a container-scoped reader assignment."
  type = object({
    account_id     = string,
    account_name   = string,
    container_name = string
    }
  )
  default = null
}

variable "backend_application_client_id" {
  description = "Optional existing single-tenant Entra API application client ID. When null, Terraform creates one; no client secret is used."
  type        = string
  default     = null
}

variable "allowed_caller_principal_ids" {
  description = "For function_only, object IDs of authorized managed identities. APIM modes use the selected APIM system identity automatically."
  type        = list(string)
  default     = []
}

variable "publish_artifacts" {
  description = "Create a temporary private deployment VM, upload package/sample assets, then set false on a second apply to remove it."
  type        = bool
  default     = true
}

variable "publisher_ssh_public_key" {
  description = "Public SSH key for the temporary VM. No public IP or inbound SSH rule is created. Required while publish_artifacts=true."
  type        = string
  default     = ""
}

variable "package_path" {
  type    = string
  default = "../.build/function.zip"
}

variable "tags" {
  type = map(string)
  default = {
    purpose = "svg-logo-demo"
  }
}

variable "lock_apim_public_access" {
  type        = bool
  default     = false
  description = "Full mode: set true only after Front Door's managed private endpoint is approved."
}
