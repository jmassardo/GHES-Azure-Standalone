# Setup the infrastructure components required to create the environment
provider "azurerm" {
  features {
  }
}

# Create a resource group to contain all the objects
resource "azurerm_resource_group" "rg" {
  name     = "${var.azure_owner}-${var.azure_rg_name}-${join("", split(":", timestamp()))}" #Add the username and remove the colons since Azure doesn't allow them.
  location = var.azure_region
  
  tags = {
    environment = var.azure_env,
    owner = var.azure_owner
  }
}

# Create the virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.azure_rg_name}-network"
  address_space       = ["10.1.0.0/16"]
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name
}

# Create the individual subnet for the servers
resource "azurerm_subnet" "subnet" {
  name                 = "${var.azure_rg_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes       = ["10.1.1.0/24"]
}

# create the network security group to allow inbound access to the servers
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.azure_rg_name}-nsg"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  # create a rule to allow HTTP inbound to all nodes in the network
  security_rule {
    name                       = "Allow_HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.source_address_prefix
    destination_address_prefix = "*"
  }
  # create a rule to allow SSL inbound to all nodes in the network
  security_rule {
    name                       = "Allow_SSL"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.source_address_prefix
    destination_address_prefix = "*"
  }
  # create a rule to allow 8443 inbound to all nodes in the network
  security_rule {
    name                       = "Allow_8443"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = var.source_address_prefix
    destination_address_prefix = "*"
  }
  # create a rule to allow SSH inbound to all nodes in the network
  security_rule {
    name                       = "Allow_SSH"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "122"
    source_address_prefix      = var.source_address_prefix
    destination_address_prefix = "*"
  }


  # add an environment tag.
  tags = {
    environment = var.azure_env,
    owner = var.azure_owner
  }
}

resource "azurerm_subnet_network_security_group_association" "sg-assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_storage_account" "asaccount" {
  name                     = "storageaccount${lower(substr(join("", split(":", timestamp())), 8, -1))}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "ascontainer" {
  name                  = "content"
  storage_account_name  = azurerm_storage_account.asaccount.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "asblob" {
  name                   = "ghescontent"
  storage_account_name   = azurerm_storage_account.asaccount.name
  storage_container_name = azurerm_storage_container.ascontainer.name
  type                   = "Block"
}