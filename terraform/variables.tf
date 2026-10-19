variable "subscription_id" { type = string }
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
    condition     = contains(["full", "existing_front_door", "function_only"], var.mode)
    error_message = "Use full, existing_front_door, or function_only."
  }
}
variable "existing_front_door" {
  description = "Existing Premium profile and endpoint. Only new logo origin group, origin and route are added."
  type        = object({ profile_name = string, resource_group_name = string, endpoint_name = string })
  default     = null
}
variable "existing_network" {
  type    = object({ vnet_id = string, function_subnet_id = string, private_endpoint_subnet_id = string, publisher_subnet_id = optional(string) })
  default = null
}
variable "private_dns_zone_ids" {
  type    = map(string)
  default = {}
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
  description = "Existing private catalog; connectivity/DNS must work. No samples are uploaded to this catalog."
  type        = object({ account_id = string, account_name = string, container_name = string })
  default     = null
}
variable "publish_artifacts" {
  description = "Temporary private publisher. Set false after verification and apply again to remove it."
  type        = bool
  default     = true
}
variable "publisher_ssh_public_key" {
  type    = string
  default = ""
}
variable "package_path" {
  type    = string
  default = "../.build/function.zip"
}
variable "tags" {
  type    = map(string)
  default = { purpose = "svg-logo-demo" }
}

variable "publisher_vm_size" {
  description = "Temporary upload VM size; choose an available x64 size in the target region."
  type        = string
  default     = "Standard_B1s"
}
