#create a public IP address for the virtual machine
resource "azurerm_public_ip" "ghe-server-pubip" {
  name                = "ghe-server-pubip"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  domain_name_label   = "ghe-server-${lower(substr(join("", split(":", timestamp())), 8, -1))}"

  tags = {
    environment = var.azure_env,
    owner = var.azure_owner
  }
}
#create the network interface and put it on the proper vlan/subnet
resource "azurerm_network_interface" "ghe-server-ip" {
  name                = "ghe-server-ip"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ghe-server-ipconf"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.ghe-server-pubip.id
  }
}

#create the actual VM
resource "azurerm_virtual_machine" "ghe-server" {
  name                  = "ghe-server"
  location              = var.azure_region
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.ghe-server-ip.id]
  vm_size               = var.vm_size

  storage_os_disk {
    name              = "ghe-server-osdisk"
    managed_disk_type = "Premium_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }
  storage_image_reference {
    publisher = "GitHub"
    offer     = "GitHub-Enterprise"
    sku       = "GitHub-Enterprise"
    version   = var.ghes_version
  }

  os_profile {
    computer_name  = "ghe-server"
    admin_username = var.username
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.username}/.ssh/authorized_keys"
      key_data = file("${var.ssh_public_key_path}")
    }
  }

  tags = {
    environment = var.azure_env,
    owner = var.azure_owner
  }
}

# add additional data disk and associate it with the VM
resource "azurerm_managed_disk" "ghe-server-datadisk" {
  name                 = "ghe-server-datadisk"
  location             = var.azure_region
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 200
}

resource "azurerm_virtual_machine_data_disk_attachment" "ghe-server-datadisk" {
  managed_disk_id    = azurerm_managed_disk.ghe-server-datadisk.id
  virtual_machine_id = azurerm_virtual_machine.ghe-server.id
  lun                = "10"
  caching            = "ReadWrite"
}

output "ghe-server-public-fqdn" {
  value = azurerm_public_ip.ghe-server-pubip.fqdn
}

# Generate the template files
data "template_file" "settings_json" {
  template = "${file("${path.module}/settings.tpl")}"
  vars = {
    ghe_fqdn = "${azurerm_public_ip.ghe-server-pubip.fqdn}"
  }
}

resource "local_file" "settings_json" {
    content     = data.template_file.settings_json.rendered
    filename = "${path.module}/settings.json"
}

# configure the server
resource "null_resource" "ghe-server-config" {
  depends_on = [
    azurerm_virtual_machine.ghe-server,
    azurerm_virtual_machine_data_disk_attachment.ghe-server-datadisk,
    azurerm_managed_disk.ghe-server-datadisk
  ]
  # Sleep
  provisioner "local-exec" {
    command = "echo \"Sleep for a few seconds to allow the api to catch up \" ; sleep 180"
  }

  # Upload the license file and set admin password
  provisioner "local-exec" {
    command = "echo \"Attempting to set license and admin password\" ; curl -k -v -X POST -H \"Accept: application/vnd.github.v3+json\" \"https://${azurerm_public_ip.ghe-server-pubip.fqdn}:8443/setup/api/start\" -F \"license=@test.ghl\" -F password=${var.password}"
  }

  # Upload the SSH key
  provisioner "local-exec" {
    command = "echo \"Attempting to upload the SSH key\" ; curl -k -v -X POST -H \"Accept: application/vnd.github.v3+json\" \"https://api_key:${var.password}@${azurerm_public_ip.ghe-server-pubip.fqdn}:8443/setup/api/settings/authorized-keys\" -F authorized_key=@${var.ssh_public_key_path}"
  }

  # Upload the settings json data
  provisioner "local-exec" {
    command = "echo \"Attempting to upload the settings\" ; curl -k -v -X PUT -H \"Accept: application/vnd.github.v3+json\" \"https://api_key:${var.password}@${azurerm_public_ip.ghe-server-pubip.fqdn}:8443/setup/api/settings\" --data-urlencode \"settings=$(cat settings.json)\""
  }

  # Trigger reconfigure
  provisioner "local-exec" {
    command = "echo \"Attempting to trigger a reconfigure\" ; curl -k -v -X POST -H \"Accept: application/vnd.github.v3+json\" \"https://api_key:${var.password}@${azurerm_public_ip.ghe-server-pubip.fqdn}:8443/setup/api/configure\""
  }

  # Wait for reconfigure to finish
  provisioner "local-exec" {
    command = "./configcheck.sh ${azurerm_public_ip.ghe-server-pubip.fqdn} ${var.password}"
  }

  # Generate a proper SSL certificate
  provisioner "remote-exec" {
    inline = [
      "echo \"Attempting to request a cert from Let's Encrypt\"",
      "ghe-ssl-acme -e",
      "echo \"Creating ${var.username} user\"",
      "echo '(User.create!(login: \"${var.username}\", email: \"${var.username}@email.com\", password: \"${var.password}\"))' | ghe-console -y",
      "echo \"Promoting user to site admin.\"",
      "ghe-user-promote ${var.username}",
      "echo \"Create new org.\"",
      "echo 'Organization.create!(login: \"${var.org_name}\", admins: [dat(\"${var.username}\")])' | ghe-console -y",
    ]
    connection {
      host     = azurerm_public_ip.ghe-server-pubip.fqdn
      type     = "ssh"
      user     = "admin"
      private_key = "${file("${var.ssh_private_key_path}")}"
      port = "122"
    }
  }

  # Set up Actions and Packages
  provisioner "remote-exec" {
    inline = [
      "ghe-config 'secrets.actions.storage.blob-provider' 'azure'",
      "ghe-config 'secrets.actions.storage.azure.connection-string' '${azurerm_storage_account.asaccount.primary_connection_string}'",
      "ghe-config 'app.actions.enabled' 'true'",
      "ghe-config 'app.packages.enabled' 'true'",
      "ghe-config 'app.hydro.enabled' 'true'",
      "ghe-config 'secrets.packages.blob-storage-type' 'azure'",
      "ghe-config 'secrets.packages.azure-connection-string' '${azurerm_storage_account.asaccount.primary_connection_string}'",
      "ghe-config 'secrets.packages.azure-container-name' 'content'",
      "ghe-config-apply",
    ]
    connection {
      host     = azurerm_public_ip.ghe-server-pubip.fqdn
      type     = "ssh"
      user     = "admin"
      private_key = "${file("${var.ssh_private_key_path}")}"
      port = "122"
    }
  }
}