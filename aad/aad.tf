variable "aad_group_names" {
  type = list(string)
  description = "list of AAD groups names to sync"
}

terraform {
  required_providers {    
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.22.0"
    }
  }
}

# read group members of given groups from AzureAD every time Terraform is started
data "azuread_group" "this" {
  for_each     = toset(var.aad_group_names)
  display_name = each.value
}

locals {
  all_members = toset(flatten([for group in values(data.azuread_group.this) : group.members]))
}


# Extract information about real users
data "azuread_users" "users" {
  ignore_missing = true
  object_ids     = local.all_members
}

locals {
  all_users = {
    for user in data.azuread_users.users.users : user.object_id => user
  }
}

# Provision Service Principals
data "azuread_service_principals" "spns" {
  ignore_missing = true
  object_ids     = toset(setsubtract(local.all_members, data.azuread_users.users.object_ids))
}

locals {
  all_spns = {
    for sp in data.azuread_service_principals.spns.service_principals : sp.object_id => sp
  }
}

output "aad" {
  value = {
    all_members_ids = local.all_members
    all_spns_by_id = local.all_spns
    all_users_by_id = local.all_users
    all_groups_by_id = {
      for name, data in data.azuread_group.this :
      data.object_id => data
    }
  }
}