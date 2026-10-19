# Terraform deployment

From the repository root:

```sh
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
npm test
python3 scripts/package.py
cp terraform/examples/full-demo/terraform.tfvars.example terraform/demo.tfvars
# Or choose existing-front-door / function-only.
```

Edit the variable file and replace every placeholder, including the SSH public key if using the temporary publisher. For existing Front Door, first [review the route paths and ownership](existing-front-door.md). Keep a separate state and variable file per installation; never change mode to adopt a different installation.

```sh
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -var-file=demo.tfvars -out=demo.tfplan
terraform -chdir=terraform apply demo.tfplan
```

Use a protected remote backend with locking for shared work. Do not commit state, plans, `.tfvars` or credentials. The root uses local state initially so you can select your organization's backend.

## Approve private origins and verify

```sh
python3 scripts/approve-front-door.py
# Review the exact resource IDs before approving:
python3 scripts/approve-front-door.py --approve
terraform -chdir=terraform output -raw demo_url
```

The approval helper reads `front_door_private_link_approvals` from this Terraform state and matches exact request messages. It does not approve unrelated pending requests. Function-only has no requests until you connect it manually.

After propagation, open the demo and run:

```sh
python3 scripts/smoke.py https://YOUR-FRONT-DOOR-HOST
```

For a reused catalog, pass `--original EXISTING_KEY --missing KNOWN_ABSENT_KEY`. In full mode, also open `/` and verify the response header `X-Demo-Origin: webapp`.

Set `publish_artifacts=false` in the **same** variable file and plan/apply again after successful verification. Terraform removes the temporary VM, NIC/NSG, upload role assignments and any temporary outbound NAT/public IP. The code package, Function and catalog remain.

## Updates and teardown

Rebuild the ZIP, temporarily enable publishing, plan/apply, verify and remove the publisher again. Hash-named packages preserve previous versions. Set a reviewed package-retention policy for longer-lived installations.

Destroying the stack deletes new Storage data. Review `terraform -chdir=terraform plan -destroy -var-file=demo.tfvars` and preserve needed data before `terraform destroy`. Referenced profile/endpoint, catalog, network and plan are not owned/deleted by this stack. The logo routes/origins this stack added to an existing profile **are** removed by destroy; other routes remain.

Use a fresh state for a new installation. If adopting previously deployed resources, review imports and the migration plan explicitly; do not accept destructive replacements as an installation shortcut.

## Private runner alternative

Apply with `publish_artifacts=false`, grant the private runner Blob Data Contributor on the host `packages` container, then run from that network:

```sh
python3 scripts/publish.py --host HOST_STORAGE_NAME --package .build/function.zip
# Add --catalog NEW_DEMO_CATALOG_NAME only to seed a newly created demo catalog.
az functionapp restart --resource-group WORKLOAD_RG --name FUNCTION_NAME
az rest --method post --url 'https://management.azure.com/subscriptions/SUBSCRIPTION_ID/resourceGroups/WORKLOAD_RG/providers/Microsoft.Web/sites/FUNCTION_NAME/syncfunctiontriggers?api-version=2024-04-01'
```

Add write permission on the new `logos` container only when seeding. `--identity` uses the runner VM's system identity instead of Azure CLI. The publisher verifies private DNS resolution and refuses to overwrite different existing content. Repeat restart/sync after each package update.
