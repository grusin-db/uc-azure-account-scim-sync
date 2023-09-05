
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "1.24.1"
    }
  }
}

provider "azuread" {
  # Configuration options
}

# configure companion mode for enterprise app (EA) sync
# WARNING: this variables MUST be set once and not changed
#   if ea_companion_mode changes from `false` (terraform maintains users) to `true` (terraform does not maintain users anymore)
#   when terraform has state file, it will be seen as request to delete users from account console
locals {
  ea_cfg = {
    ea_companion_mode: false
    ea_application_id: "",
  }
}

# TODO: update your databricks connection details here
provider "databricks" {
  host       = "https://accounts.azuredatabricks.net"
  account_id = "c3d0c960-58a1-4b23-b7f5-de6ca6fc1e2b"
}

# TODO: update this with storage where state will be kept
terraform {
  backend "azurerm" {
    subscription_id      = "e54189ca-0061-4994-a1ae-c82d189a0b0e"
    resource_group_name  = "playground"
    storage_account_name = "ucadmintfstatedev"
    container_name       = "tfstate"
    key                  = "scim-sync.tfstate"
    use_azuread_auth     = true
  }
}
  