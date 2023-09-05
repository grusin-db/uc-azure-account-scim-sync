# Azure AAD to Databricks Account SCIM Sync

End to end synchronization of the whitelisted list of AAD groups into Databricks Account. **Users**, **Groups**, **SPNs** that are members of whitelisted groups are synchronized. Nested groups are supported.



![use terraform](./docs/use_terraform.png)

## How to run syncing

1. Edit `cfg/groups_to_sync.json`, set whitelisted list of groups to sync. Contents if this file will most likely evolve as more teams are onboarded to UC, new groups added to this file will be automatically picked up on next terraform run.

1. Edit `cfg/account_admin_groups.json`, set list of aad groups whose members should be added as account admins, **this is very important step**, as of now the terraform resets admins defined in account console if they are not defined in this file. Contents of this file can evolve with time as well.

1. Edit `providers.tf`
  
- update connection details for databricks account console
- update connection details for terraform blob storage backend
- update EA companion mode flag, when `true` terraform will not maintain users, this functionality will be performed by EA. Groups, and SPNs are always maintained disregard of value of this flag.

1. Run `sh sync.sh`, it will do all the syncing for you
1. Optionally run `sh sync_ea.sh`, to update list of groups EA syncs

### EA Companion mode

The application allows also running in enteprise app "companion mode", where users will be maintained by EA, but Groups and SPNs are mantained by terraform. Optionally we can set list of groups that EA syncs, so that this does not needs to be performed manually via EA UI.

To enable "companion mode" mode set `ea_companion_mode` to `true` in `providers.tf`

The syncing of groups that EA uses is handled by `sync_aad_groups_to_ea.py`, to run it create `sync_ea.sh` with contents:

```sh
python3 sync_aad_groups_to_ea.py \
  --app_name "Azure_Databricks_SCIM_Provisioning_Connector" \
  --tenant_id "83d7850c-d919-43de-a8dd-dd30c5353e52" \
  --spn_id "bab70a68-a7aa-43bc-909f-cd3fc8f38026" \
  --spn_key "[redacted]"
```

and run it, it will use groups defined in `.aad_state.json` file. 

See `python3 sync_aad_groups_to_ea.py --help` for list of all options:
```
usage: sync_aad_groups_to_ea.py [-h] --app_name APP_NAME --tenant_id TENANT_ID --spn_id SPN_ID --spn_key SPN_KEY [--json_file_name JSON_FILE_NAME]
                                [--verbose] [--dry_run] [--only_add]

options:
  -h, --help            show this help message and exit
  --app_name APP_NAME   Enterprise Application Name
  --tenant_id TENANT_ID
                        Azure Tenant Id
  --spn_id SPN_ID       Deployment SPN Id
  --spn_key SPN_KEY     Deployment SPN Secret Key
  --json_file_name JSON_FILE_NAME
                        JSON file containing all groups
  --verbose             Verbose logs
  --dry_run             Prints action, but does not do any changes
  --only_add            Only adds groups to EA, never removes
```

**WARNING**: `ea_companion_mode` **flag MUST be set once and not changed when terraform has ran for first time (has a state file)**

if `ea_companion_mode` changes from `false` (terraform maintains users) to `true` (terraform does not maintain users anymore). it will be seen as request to delete users from the account console. EA app of course at this point would add users back again, but for period between runs there would be no users in account console.

## How it works

I’ve ran into depdendency bug in TF, that was causing havoc in planning. Due to this I needed to split code into two terraform applications.

First terraform application, placed in `aad/` folder, does only download aad groups, members, spns, users… and builds all the parameters for the 2nd terraform application. This application does a bit of conditional filtering of members of each of the groups, to make sure that only nested groups which were white listed are included. Results of this data massaging task are written to `.aad_state.json`. This application does not need state.

Second terraform application just goes and applies the known set of resources, without doing any AAD checks. Having the intermediate state written to the json file is a workaround for the "nasty TF bug". This application needs state to handle deletions. State is kept in blob storage defined in `providers.tf`

To run all of this just run `sh sync.sh` :)

## Known limitations / bugs

- acount admins who are not defined in `cfg/account_admin_groups.json` will be removed from the account console on first run when `ea_companion_mode = false` (terraform is responsbile for syncing users). [databricks provider github issue tracker](https://github.com/databricks/terraform-provider-databricks/issues/2648)
- users, groups, or spns added via account console are not deleted by this application
- members of groups added via account console are not deleted by this application
- users having emails containing quote character will not be synced. [databricks provider github issue tracker](https://github.com/databricks/terraform-provider-databricks/issues/2646)
- groups defined in `cfg/groups_to_sync.json` must be valid AAD groups

I will be trying to resolve these two issues, but this should be lesser of a problem because access to account console group membership should be heavily restricted.

## Credits

- Code in this repo is heavily based on work of Alex Ott @ Databricks (https://github.com/alexott/terraform-playground/tree/main/aad-dbx-sync).
- Code for EA sync (`sync_aad_groups_to_ea.py`) is based on work of Shasidhar Eranti @ Databricks
