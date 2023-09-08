locals {
  # .aad_state.json is prepared by ./aad module
  aad_state_raw = jsondecode(file("${path.module}/.aad_state.json"))
  aad_state     = local.aad_state_raw.aad_state.value
}

# validate that account admin group exists
data "databricks_group" "admins" {
  for_each     = local.aad_state.account_admin_groups_by_id
  display_name = each.value.display_name
  recursive    = false
}

# set admin group the admin rights
resource "databricks_group_role" "acount_admins" {
  for_each = local.aad_state.account_admin_groups_by_id
  group_id = data.databricks_group.admins[each.key].id
  role     = "account_admin"
  depends_on = [
    data.databricks_group.admins
  ]
}

# create or remove groups within databricks - all governed by "groups_to_sync" variable
# indexed by AAD object_id of a group
# skip admin groups, so that it does not reset admin priviledges
resource "databricks_group" "this" {
  for_each = {
    for group_id, data in local.aad_state.groups_by_id :
    group_id => data
    if lookup(local.aad_state.account_admin_groups_by_id, group_id, "") == ""
  }
  display_name = each.value.display_name
  force        = true
  depends_on = [
    databricks_group_role.acount_admins
  ]
}

# create or remove users from databricks account
# indexes by AAD User object_id
# when ea's companion mode is enabled, EA handles syncing of users
resource "databricks_user" "this" {
  for_each = {
    for u, v in local.aad_state.users_by_id :
    u => v
    if local.ea_cfg.ea_companion_mode == false
  }
  user_name    = lower(each.value.user_principal_name)
  display_name = each.value.display_name
  active       = each.value.account_enabled
  force        = true
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
  merged_data = merge(databricks_user.this, databricks_service_principal.this, databricks_group.this, data.databricks_group.admins)
}

# assing users, spns and groups as members of the groups
# jsonencode and decode is there because for each can only works on strings, and we need to pass two values
# map(group -> member) wont work here, because there will be multiple members per each group
resource "databricks_group_member" "this" {
  for_each = {
    for x in local.aad_state.group_members_mapping :
    "${x.aad_group_id}|${x.aad_member_id}" => x
    if lookup(local.merged_data, x.aad_member_id, "") != ""
  }
  group_id  = local.merged_data[each.value.aad_group_id].id
  member_id = local.merged_data[each.value.aad_member_id].id
}
