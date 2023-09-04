locals {
  # .aad_state.json is prepared by ./aad module
  aad_state_raw  = jsondecode(file("${path.module}/.aad_state.json"))
  aad_state = local.aad_state_raw.aad_state.value
}

# create or remove groups within databricks - all governed by "groups_to_sync" variable
# indexed by AAD object_id of a group
resource "databricks_group" "this" {
  for_each =  local.aad_state.groups_by_id
  display_name = each.value.display_name
  force        = true
}

# create or remove users from databricks account
# indexes by AAD User object_id
resource "databricks_user" "this" {
  for_each     = local.aad_state.users_by_id
  user_name    = lower(each.value.user_principal_name)
  display_name = each.value.display_name
  active       = each.value.account_enabled
  force        = true
}

# set account admins
resource "databricks_user_role" "my_user_account_admin" {
  for_each = local.aad_state.admin_users_by_id
  user_id  = databricks_user.this[each.key].id
  role     = "account_admin"
}

# create service principals in databricks account console
# indexed by AAD SPN object_id
resource "databricks_service_principal" "this" {
  for_each       = local.aad_state.spns_by_id
  application_id = each.value.application_id
  display_name   = each.value.display_name
  active         = each.value.account_enabled
  force          = true
}

locals {
  merged_data = merge(databricks_user.this, databricks_service_principal.this, databricks_group.this)
}

# assing users, spns and groups as members of the groups
# jsonencode and decode is there because for each can only works on strings, and we need to pass two values
# map(group -> member) wont work here, because there will be multiple members per each group
resource "databricks_group_member" "this" {
  for_each  = {
    for x in local.aad_state.group_members_mapping :
    "${x.aad_group_id}|${x.aad_member_id}" => x
  }
  group_id  = local.merged_data[each.value.aad_group_id].id
  member_id = local.merged_data[each.value.aad_member_id].id
}
