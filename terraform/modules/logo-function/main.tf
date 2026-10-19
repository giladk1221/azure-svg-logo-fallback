variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "integration_subnet_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_ids" {
  type = map(string)
}

variable "existing_service_plan_id" {
  type    = string
  default = null
}

variable "plan_sku" {
  type = string
}

variable "existing_catalog" {
  type    = any
  default = null
}

variable "backend_application_client_id" {
  type    = string
  default = null
}

variable "allowed_caller_principal_ids" {
  type = list(string)
}

variable "package_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  catalog_id   = var.existing_catalog == null ? azurerm_storage_account.catalog[0].id : var.existing_catalog.account_id
  catalog_name = var.existing_catalog == null ? azurerm_storage_account.catalog[0].name : var.existing_catalog.account_name
  container    = var.existing_catalog == null ? "logos" : var.existing_catalog.container_name
  client_id    = var.backend_application_client_id == null ? azuread_application.backend[0].client_id : var.backend_application_client_id
  audience     = "api://${local.client_id}"
  endpoints = merge({
    blob = azurerm_storage_account.host.id,
    }
    , var.existing_catalog == null ? {
      catalog = local.catalog_id
      } : {
    }
  )
}

resource "azurerm_user_assigned_identity" "function" {
  name                = "${var.name}-function-mi"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_storage_account" "host" {
  name                            = "${var.name}host"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }

  tags = var.tags
}

resource "azurerm_storage_account" "catalog" {
  count                           = var.existing_catalog == null ? 1 : 0
  name                            = "${var.name}logos"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }

  tags = var.tags
}

# ARM container resources avoid a data-plane connection from the Terraform laptop.
resource "azapi_resource" "packages" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  parent_id = "${azurerm_storage_account.host.id}/blobServices/default"
  name      = "packages"
  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azapi_resource" "logos" {
  count     = var.existing_catalog == null ? 1 : 0
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  parent_id = "${local.catalog_id}/blobServices/default"
  name      = "logos"
  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_private_endpoint" "storage" {
  for_each            = local.endpoints
  name                = "${var.name}-${each.key}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  private_service_connection {
    name                           = "${each.key}-connection"
    private_connection_resource_id = each.value
    subresource_names              = [each.key == "catalog" ? "blob" : each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids[each.key == "catalog" ? "blob" : each.key]]
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "host" {
  for_each                         = toset(["Storage Blob Data Owner"])
  scope                            = azurerm_storage_account.host.id
  principal_id                     = azurerm_user_assigned_identity.function.principal_id
  role_definition_name             = each.value
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "catalog_reader" {
  scope                            = "${local.catalog_id}/blobServices/default/containers/${local.container}"
  principal_id                     = azurerm_user_assigned_identity.function.principal_id
  role_definition_name             = "Storage Blob Data Reader"
  skip_service_principal_aad_check = true
  depends_on                       = [azapi_resource.logos]
}

resource "azuread_application" "backend" {
  count            = var.backend_application_client_id == null ? 1 : 0
  display_name     = "${var.name}-logo-api"
  sign_in_audience = "AzureADMyOrg"
}

resource "azuread_application_identifier_uri" "backend" {
  count          = var.backend_application_client_id == null ? 1 : 0
  application_id = azuread_application.backend[0].id
  identifier_uri = local.audience
}

resource "azuread_service_principal" "backend" {
  count     = var.backend_application_client_id == null ? 1 : 0
  client_id = azuread_application.backend[0].client_id
}

resource "azurerm_log_analytics_workspace" "demo" {
  name                = "${var.name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "demo" {
  name                = "${var.name}-insights"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.demo.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_service_plan" "demo" {
  count               = var.existing_service_plan_id == null ? 1 : 0
  name                = "${var.name}-plan"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.plan_sku
  tags                = var.tags
}

resource "azurerm_linux_function_app" "demo" {
  name                                           = "${var.name}-function"
  location                                       = var.location
  resource_group_name                            = var.resource_group_name
  service_plan_id                                = var.existing_service_plan_id == null ? azurerm_service_plan.demo[0].id : var.existing_service_plan_id
  storage_account_name                           = azurerm_storage_account.host.name
  storage_uses_managed_identity                  = true
  virtual_network_subnet_id                      = var.integration_subnet_id
  public_network_access_enabled                  = false
  https_only                                     = true
  functions_extension_version                    = "~4"
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.function.id]
  }

  site_config {
    always_on               = true
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    ftps_state              = "Disabled"
    application_stack {
      node_version = "22"
    }

    application_insights_connection_string = azurerm_application_insights.demo.connection_string
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME                     = "node"
    AzureWebJobsStorage__credential              = "managedidentity"
    AzureWebJobsStorage__clientId                = azurerm_user_assigned_identity.function.client_id
    AZURE_CLIENT_ID                              = azurerm_user_assigned_identity.function.client_id
    LOGO_STORAGE_ACCOUNT                         = local.catalog_name
    LOGO_CONTAINER                               = local.container
    WEBSITE_RUN_FROM_PACKAGE                     = "https://${azurerm_storage_account.host.name}.blob.core.windows.net/packages/${var.package_name}"
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = azurerm_user_assigned_identity.function.id
  }

  auth_settings_v2 {
    auth_enabled           = true
    require_authentication = true
    unauthenticated_action = "Return401"
    default_provider       = "azureactivedirectory"
    require_https          = true
    active_directory_v2 {
      client_id            = local.client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
      allowed_audiences    = [local.audience, local.client_id]
      allowed_identities   = var.allowed_caller_principal_ids
    }

    login {
      token_store_enabled = false
    }
  }

  lifecycle {
    precondition {
      condition     = length(var.allowed_caller_principal_ids) > 0
      error_message = "At least one gateway/caller identity must be explicitly authorized."
    }
  }

  depends_on = [azurerm_role_assignment.host, azurerm_role_assignment.catalog_reader, azurerm_private_endpoint.storage, azuread_application_identifier_uri.backend, azuread_service_principal.backend]
  tags       = var.tags
}

resource "azurerm_private_endpoint" "function" {
  name                = "${var.name}-function-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  private_service_connection {
    name                           = "function"
    private_connection_resource_id = azurerm_linux_function_app.demo.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids["sites"]]
  }

  tags = var.tags
}

output "name" {
  value = azurerm_linux_function_app.demo.name
}

output "hostname" {
  value = azurerm_linux_function_app.demo.default_hostname
}

output "backend_audience" {
  value = local.audience
}

output "host_storage_id" {
  value = azurerm_storage_account.host.id
}

output "host_storage_name" {
  value = azurerm_storage_account.host.name
}

output "catalog_storage_id" {
  value = local.catalog_id
}

output "catalog_storage_name" {
  value = local.catalog_name
}

output "id" {
  value = azurerm_linux_function_app.demo.id
}
