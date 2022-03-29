# Azure Options
variable "azure_region" {
  default     = "eastus" # Use region shortname here as it's interpolated into the URLs
  description = "The location/region where the resources are created."
}

variable "azure_owner" {
  default     = "MyGitHubHandle"
  description = "The owner of the resources."
}

variable "azure_env" {
  default     = "Dev"
  description = "This is the name of the environment tag, i.e. Dev, Test, etc."
}

variable "azure_rg_name" {
  default     = "lab" # This will get a unique timestamp appended
  description = "Specify the name of the new resource group"
}

# Shared Options

variable "username" {
  default     = "gheadmin"
  description = "Admin username for all VMs"
}

variable "password" {
  default     = "P-ssw0rd1234"
  description = "Admin password for all VMs"
}

variable "vm_size" {
  default     = "Standard_E8ds_v4"
  description = "Specify the VM Size"
}

variable "source_address_prefix" {
  default     = "*"
  description = "Limit who can access this resource"
}

variable "ghes_version" {
  default = "3.3.5"
  description = "Specify the version of the GHES"
}

variable "ssh_public_key_path" {
  default = "/home/vscode/.ssh/terraform.pub"
  description = "Path to the desired public SSH key. This will be uploaded to the instance to enable ssh access"
}

variable "ssh_private_key_path" {
  default = "/home/vscode/.ssh/terraform"
  description = "Path to the desired private SSH key. This is used to remotely execute commands"
}

variable "org_name" {
  default = "ghe-lab"
  description = "The name of the organization to create"
}