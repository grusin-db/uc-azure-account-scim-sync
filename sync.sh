#!/bin/sh
terraform -chdir=aad init  &&
terraform -chdir=aad apply --auto-approve &&
terraform -chdir=aad output -json > .aad_state.json &&
terraform init &&
terraform apply --auto-approve
