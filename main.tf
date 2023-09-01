variable "groups_to_sync" {
  type = list(string)
  description = "list of AAD groups names to sync"
}

# read group members of given groups from AzureAD every time Terraform is started
data "azuread_group" "this" {
  for_each     = toset(var.groups_to_sync)
  display_name = each.value
}

# create or remove groups within databricks - all governed by "groups_to_sync" variable
# indexed by AAD object_id of a group
resource "databricks_group" "this" {
  for_each = {
    for group_name, data in data.azuread_group.this :
    data.object_id => data
  }
  display_name = each.value.display_name
  force        = true
}

locals {
  all_members = toset(flatten([for group in values(data.azuread_group.this) : group.members]))
}

#
# Users
#

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

# all governed by AzureAD, create or remove users from databricks workspace
resource "databricks_user" "this" {
  for_each     = local.all_users
  user_name    = lower(local.all_users[each.key]["user_principal_name"])
  display_name = local.all_users[each.key]["display_name"]
  active       = local.all_users[each.key]["account_enabled"]
  force        = true
}

#
# Service Principals
#

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

# create service principals in databricks account console
# indexed by SPN's application_id
resource "databricks_service_principal" "sp" {
  for_each       = local.all_spns
  application_id = local.all_spns[each.key]["application_id"]
  display_name   = local.all_spns[each.key]["display_name"]
  active         = local.all_spns[each.key]["account_enabled"]
  force          = true
}

#
# Group membership
#

locals {
  all_account_ids = merge(databricks_user.this, databricks_service_principal.sp, databricks_group.this)
}

# # assing users, spns and groups as members of the groups
# resource "databricks_group_member" "this" {
#   for_each  = toset(flatten([
#     for group, details in data.azuread_group.this : [
#       for member in details["members"] : jsonencode({
#         group_id  = databricks_group.this[details.object_id].id,
#         member_id = lookup(lookup(local.all_account_ids, member, {}), "id", 0)
#       })
#       if lookup(lookup(local.all_account_ids, member, {}), "id", 0) > 0
#   ]]))
#   group_id  = jsondecode(each.value).group_id
#   member_id = jsondecode(each.value).member_id
# }

locals {
  merged_data = merge(databricks_user.this, databricks_service_principal.sp)
}

// put users to respective groups
resource "databricks_group_member" "this" {
  for_each = toset(flatten([
    for group, details in data.azuread_group.this : [
      for member in details["members"] : jsonencode({
        group  = databricks_group.this[group].id,
        member = local.merged_data[member].id
      })
    ]
  ]))
  group_id  = jsondecode(each.value).group
  member_id = jsondecode(each.value).member
}
