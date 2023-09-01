
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "1.24.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.22.0"
    }
  }
}

provider "azuread" {
  # Configuration options
}

# update your databricks connection details here
provider "databricks" {
  host       = "https://accounts.azuredatabricks.net"
  account_id = "c3d0c960-58a1-4b23-b7f5-de6ca6fc1e2b"
}

# # update this with storage where state will be kept
# terraform {
#   backend "azurerm" {
#     subscription_id      = "e54189ca-0061-4994-a1ae-c82d189a0b0e"
#     resource_group_name  = "playground"
#     storage_account_name = "ucadmintfstatedev"
#     container_name       = "tfstate"
#     key                  = "scim-sync.tfstate"
#     use_azuread_auth     = true
#   }
# }
  