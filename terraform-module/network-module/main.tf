provider "azurerm" {
  features {}
}

# Network
# Create a virtual network within the resource group
resource "azurerm_virtual_network" "network" {
  name                = "${var.resource-group.name}-network"
  address_space       = ["10.0.0.0/16"]
  location            = var.resource-group.location
  resource_group_name = var.resource-group.name
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.resource-group.name}-subnet"
  resource_group_name  = var.resource-group.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefix       = "10.0.1.0/24"
}

resource "azurerm_network_security_group" "nsgs" {
  location = var.resource-group.location
  name = "${var.resource-group.name}-nsgs"
  resource_group_name = var.resource-group.name
}

resource "azurerm_network_security_rule" "all_in" {
  access = "Allow"
  direction = "Inbound"
  name = "Accept All In"
  network_security_group_name = azurerm_network_security_group.nsgs.name
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
  network_security_group_name = azurerm_network_security_group.nsgs.name
  priority = 100
  protocol = "*"
  resource_group_name = var.resource-group.name
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_subnet_network_security_group_association" "nsgs-subnet" {
  network_security_group_id = azurerm_network_security_group.nsgs.id
  subnet_id = azurerm_subnet.subnet.id
}