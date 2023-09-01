# Azure AAD to Databricks Account SCIM Sync

End to end synchronization of the whitelisted list of AAD groups into Databricks Account. **Users**, **Groups**, **SPNs** that are members of whitelisted groups are synchronized. Nested groups are supported.

![use terraform](./docs/use_terraform.png)

## How to run

1. populate `groups_to_sync.json` with whitelisted list of groups to sync
1. edit `providers.tf` and update connection details for databricks and terraform blob storage backend
1. run `sh sync.sh`, it will do all the syncing for you

## How it works

I’ve ran into depdendency bug in TF, that was causing havoc in planning. Due to this I needed to split code into two terraform applications.

First terraform application, placed in `aad/` folder, does only download aad groups, members, spns, users… and builds all the parameters for the 2nd terraform application. This application does a bit of conditional filtering of members of each of the groups, to make sure that only nested groups which were white listed are included. Results of this data massaging task are written to `.aad_state.json`. This application does not need state.

Second terraform application just goes and applies the known set of resources, without doing any AAD checks. Having the intermediate state written to the json file is a workaround for the "nasty TF bug". This application needs state to handle deletions. State is kept in blob storage defined in `providers.tf`

To run all of this just run `sh sync.sh` :)

## Known limitations

- users, groups, or spns added via account console are not deleted by this application
- members of groups added via account console are not deleted by this application

I will be trying to resolve these two issues, but this should be lesser of a problem because access to account console group membership should be heavily restricted.
