#!/bin/sh
terraform -chdir=aad init &&
terraform -chdir=aad apply --auto-approve > /dev/null &&
terraform -chdir=aad output -json > .aad_state.json &&
terraform init &&
terraform apply 
