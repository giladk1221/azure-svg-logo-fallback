variable "vm_size" {
  type = string
}

variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "create_outbound_nat" {
  type = bool
}

variable "ssh_public_key" {
  type = string
}

variable "host_storage_id" {
  type = string
}

variable "host_storage_name" {
  type = string
}

variable "catalog_storage_id" {
  type = string
}

variable "catalog_storage_name" {
  type = string
}

variable "seed_catalog" {
  type = bool
}

variable "package_name" {
  type = string
}

variable "package_path" {
  type = string
}

variable "assets_path" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  payload = base64encode(jsonencode({
    host         = var.host_storage_name
    catalog      = var.catalog_storage_name
    package_name = var.package_name
    package      = filebase64(var.package_path)
    assets = var.seed_catalog ? {
      for f in fileset(var.assets_path, "*.svg") :
      f => filebase64("${var.assets_path}/${f}")
      } : {
    }
    }
  ))
  publisher = file("${path.module}/../../../scripts/publish.py")
  script = templatefile("${path.module}/run.sh.tftpl", {
    publisher = local.publisher,
    payload   = local.payload
    }
  )
}

resource "azurerm_public_ip" "egress" {
  count               = var.create_outbound_nat ? 1 : 0
  name                = "${var.name}-publisher-egress"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
  # Preserve IP tags assigned by the Azure platform or subscription policy.
  lifecycle {
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_nat_gateway" "publisher" {
  count               = var.create_outbound_nat ? 1 : 0
  name                = "${var.name}-publisher-nat"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "publisher" {
  count                = var.create_outbound_nat ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.publisher[0].id
  public_ip_address_id = azurerm_public_ip.egress[0].id
}

resource "azurerm_subnet_nat_gateway_association" "publisher" {
  count          = var.create_outbound_nat ? 1 : 0
  subnet_id      = var.subnet_id
  nat_gateway_id = azurerm_nat_gateway.publisher[0].id
}

resource "azurerm_network_security_group" "publisher" {
  name                = "${var.name}-publisher-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  security_rule {
    name                       = "DenyInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "publisher" {
  name                = "${var.name}-publisher-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  ip_configuration {
    name                          = "private"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "publisher" {
  network_interface_id      = azurerm_network_interface.publisher.id
  network_security_group_id = azurerm_network_security_group.publisher.id
}

resource "azurerm_linux_virtual_machine" "publisher" {
  name                            = "${var.name}-publisher"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = "publisher"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.publisher.id]
  admin_ssh_key {
    username   = "publisher"
    public_key = var.ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags       = var.tags
  depends_on = [azurerm_network_interface_security_group_association.publisher, azurerm_subnet_nat_gateway_association.publisher, azurerm_nat_gateway_public_ip_association.publisher]
}

resource "azurerm_role_assignment" "upload" {
  for_each = merge({
    packages = "${var.host_storage_id}/blobServices/default/containers/packages"
    }
    , var.seed_catalog ? {
      logos = "${var.catalog_storage_id}/blobServices/default/containers/logos"
      } : {
    }
  )
  scope                            = each.value
  principal_id                     = azurerm_linux_virtual_machine.publisher.identity[0].principal_id
  role_definition_name             = "Storage Blob Data Contributor"
  skip_service_principal_aad_check = true
}

resource "azapi_resource" "upload" {
  type      = "Microsoft.Compute/virtualMachines/runCommands@2024-07-01"
  parent_id = azurerm_linux_virtual_machine.publisher.id
  name      = "publish-${substr(sha256(local.script), 0, 12)}"
  location  = var.location
  body = {
    properties = {
      source = {
        script = local.script
      }

      asyncExecution                  = false
      timeoutInSeconds                = 1800
      treatFailureAsDeploymentFailure = true
    }
  }

  depends_on = [azurerm_role_assignment.upload]
}
