# Deploy with Terraform

[Back to README](../README.md) · Complete [setup](deployment.md) first. Run commands from the repository root.

For only the Function, use the focused [quick start](function-only.md). For separately owned optional components, see [component deployment](components.md).

## 1. Choose one option

Set `TF_OPTION` to **one** value from this table:

| Value | Deployment |
|---|---|
| `full-demo` | Everything, including new Front Door and Web App |
| `logo-only` | Function/dependencies + new Front Door/WAF; no Web App |
| `existing-front-door` | Function/dependencies and logo routing on an existing Premium endpoint |
| `function-only` | Function/dependencies; you attach Front Door yourself |

```sh
TF_OPTION=full-demo
cp "terraform/examples/$TF_OPTION/terraform.tfvars.example" terraform/demo.tfvars
```

Edit `terraform/demo.tfvars`:

| Setting | Value to enter |
|---|---|
| `subscription_id` | Your selected Azure subscription ID |
| `name_prefix` | 3–12 lowercase letters/digits, starting with a letter; Terraform appends a unique suffix |
| `location` | Your supported region, for example `westeurope` |
| `publisher_ssh_public_key` | Complete SSH public key from setup |
| `publisher_vm_size` | Optional override if `Standard_B1s` is unavailable |
| `existing_front_door` | Existing-profile option only: profile name, resource group and endpoint name |

Keep the example's `mode` and `publish_artifacts=true`. For either existing-environment option, review [integration and optional reuse inputs](existing-front-door.md). Use a fresh state for each installation; do not switch `mode` to repurpose a deployed stack.

## 2. Package, review and deploy

```sh
python3 scripts/package.py
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -var-file=demo.tfvars -out=demo.tfplan
# Inspect the plan, then apply the saved plan:
terraform -chdir=terraform apply demo.tfplan
terraform -chdir=terraform output
```

The default is local state. Protect state/plans and use a remote backend with locking for shared work; never commit them. A failed apply can leave resources: correct the reported cause, then plan/apply with the **same** state and variables.

## 3. Connect the private origin

**Full / logo-only / existing Front Door:** review the matching Private Link requests, then approve:

```sh
python3 scripts/approve-front-door.py
python3 scripts/approve-front-door.py --approve
terraform -chdir=terraform output -raw demo_url
```

The helper reads this stack's outputs and matches exact request messages. Full mode approves both Function and Web App; logo-only and existing-profile modes approve only the Function. If Azure has not created the matching request yet, wait and rerun.

**Function only:** skip the approval helper for now. Read the outputs below and follow the [manual integration steps](existing-front-door.md#function-only); there is no Front Door URL until you do so.

```sh
terraform -chdir=terraform output -raw function_id
terraform -chdir=terraform output -raw function_hostname
```

## 4. Open and test

After Private Link approval and edge propagation, open `demo_url` (`https://YOUR-FRONT-DOOR-HOST/logos/demo`), then run:

```sh
python3 scripts/smoke.py https://YOUR-FRONT-DOOR-HOST
```

Use the hostname **without** `/logos/demo` in this command. The [testing guide](testing.md) shows expected images/status codes, reused-catalog flags and troubleshooting. Full mode also serves the Web App at `/`.

## 5. Remove the temporary uploader

After successful testing, change **`publish_artifacts = false`** in the same `terraform/demo.tfvars`, then:

```sh
terraform -chdir=terraform plan -var-file=demo.tfvars -out=publisher-cleanup.tfplan
# Confirm only temporary publisher resources/actions are removed:
terraform -chdir=terraform apply publisher-cleanup.tfplan
```

This removes the VM, disk, NIC/NSG, upload roles and any temporary NAT/public IP. The Function, package, original logos and Front Door continue running. Charges for those retained services continue.

## Update the Function later

Change the code, rebuild with `python3 scripts/package.py`, set `publish_artifacts=true`, and repeat steps 2–5. Keep the same state and configuration. Hash-named packages retain previous versions; define package retention for long-lived deployments. A private runner can follow the [manual publishing procedure](deployment.md#private-runner-alternative).

## Delete this installation

This deletes newly created Storage and its data. Back up anything needed and review the destroy plan:

```sh
terraform -chdir=terraform plan -destroy -var-file=demo.tfvars -out=destroy.tfplan
terraform -chdir=terraform apply destroy.tfplan
terraform -chdir=terraform state list
```

Referenced Front Door parents, catalog, network and plan are not deleted. Logo routes/origins and role assignments added by this stack **are** removed, including those on shared resources. Never delete a shared resource group as a shortcut. Keep state until teardown has completed.
