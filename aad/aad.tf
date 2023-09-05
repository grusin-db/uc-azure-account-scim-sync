locals {
  account_admins_aad_group_names = distinct([
    for g in jsondecode(file("${path.module}/../cfg/account_admin_groups.json")) :
    lower(g)
  ])

  aad_group_names = distinct([
    for g in concat(jsondecode(file("${path.module}/../cfg/groups_to_sync.json")), local.account_admins_aad_group_names) :
    lower(g)
  ])

}

provider "azuread" {
  # Configuration options
}

terraform {
  required_providers {    
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.22.0"
    }
  }
}

# filter only existing groups
data "azuread_groups" "this" {
  display_names = local.aad_group_names
  ignore_missing = true
}

# read group members of given groups from AzureAD every time Terraform is started
data "azuread_group" "this" {
  for_each     = toset(data.azuread_groups.this.display_names)
  display_name = each.value
}

# read admin group members
data "azuread_group" "admins" {
  for_each     = toset(local.account_admins_aad_group_names)
  display_name = each.value
}

locals {
  all_groups_members_ids = toset(flatten([for group in values(data.azuread_group.this) : group.members]))
  groups_by_id = {
    for name, data in data.azuread_group.this :
    data.object_id => data
  }
  account_admin_groups_by_id = {
    for name, data in data.azuread_group.admins :
    data.object_id => data
  }

}

# Extract information about real users
data "azuread_users" "users" {
  ignore_missing = true
  object_ids     = local.all_groups_members_ids
}

locals {
  users_by_id = {
    for user in data.azuread_users.users.users : 
    user.object_id => user
    if length(regexall("'", user.user_principal_name)) == 0
  }
}

# Provision Service Principals
data "azuread_service_principals" "spns" {
  ignore_missing = true
  object_ids     = toset(setsubtract(local.all_groups_members_ids, data.azuread_users.users.object_ids))
}

locals {
  spns_by_id = {
    for sp in data.azuread_service_principals.spns.service_principals : sp.object_id => sp
  }
}

locals {
  valid_ids = setunion(
    keys(local.groups_by_id), 
    keys(local.spns_by_id),
    keys(local.users_by_id)
  )
  group_members_mapping = toset(flatten([
    for group, details in data.azuread_group.this : [
      for member in details["members"] : {
        aad_group_id  = details.object_id
        aad_member_id = member
      }
      if contains(local.valid_ids, member)
    ]
  ]))
  skipped_group_members_mapping = toset(flatten([
    for group, details in data.azuread_group.this : [
      for member in details["members"] : {
        aad_group_id  = details.object_id
        aad_member_id = member
      }
      if !contains(local.valid_ids, member)
    ]
  ]))
}

output "aad_state" {
  value = {
    aad_group_names = local.aad_group_names
    account_admins_aad_group_names = local.account_admins_aad_group_names

    groups_by_id = local.groups_by_id
    account_admin_groups_by_id = local.account_admin_groups_by_id
    
    spns_by_id = local.spns_by_id
    users_by_id = local.users_by_id
   
    group_members_mapping = local.group_members_mapping
    skipped_group_members_mapping = local.skipped_group_members_mapping
  }
}
