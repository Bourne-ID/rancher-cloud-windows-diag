provider "azurerm" {
  features {}
}

locals {
  prefix = var.prefix
  commandToExecute = replace(replace(var.join-command, "PowerShell -NoLogo -NonInteractive -Command \"& {", ""), " | iex}\"", " --worker | powershell")
}

resource "azurerm_network_security_group" "vmss-nsgs" {
  location = var.resource-group.location
  name = "${local.prefix}-nsgs"
  resource_group_name = var.resource-group.name
}

resource "azurerm_network_security_rule" "all_in" {
  access = "Allow"
  direction = "Inbound"
  name = "Accept All In"
  network_security_group_name = azurerm_network_security_group.vmss-nsgs.name
  priority = 100
  protocol = "*"
  resource_group_name = var.resource-group.name
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "all_out" {
  access = "Allow"
  direction = "Outbound"
  name = "Accept All Out"
  network_security_group_name = azurerm_network_security_group.vmss-nsgs.name
  priority = 100
  protocol = "*"
  resource_group_name = var.resource-group.name
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_windows_virtual_machine_scale_set" "vmss" {
  name                  = "${local.prefix}-vmss"
  instances             = var.node-count
  location              = var.resource-group.location
  resource_group_name   = var.resource-group.name
  sku                   = var.node-definition.size
  overprovision         = false

  admin_username        = var.node-definition.admin-username
  admin_password        = var.node-definition.admin-password

  source_image_reference {
    publisher = var.node-definition.publisher
    offer     = var.node-definition.offer
    sku       = var.node-definition.sku
    version   = var.node-definition.version
  }

  os_disk {
    storage_account_type = var.node-definition.disk-type
    caching = "ReadWrite"
  }

  network_interface {
    name = "${local.prefix}-NodeNetwork"
    primary = true
    network_security_group_id = azurerm_network_security_group.vmss-nsgs.id


    ip_configuration {
      name = "internal"
      primary = true
      subnet_id = var.subnet-id
      public_ip_address {
        name = "${local.prefix}-publicIp"
      }
    }
  }
  lifecycle {
    ignore_changes = [instances]
  }
}

resource "azurerm_virtual_machine_scale_set_extension" "join-rancher" {
  name = "JoinRancher"
  virtual_machine_scale_set_id = azurerm_windows_virtual_machine_scale_set.vmss.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = "{ \"commandToExecute\": \"${replace(local.commandToExecute, "--worker", "--worker")}\" }"

}