# Deploy with Azure CLI

[Back to README](../README.md) · Complete [setup](deployment.md) first. Run commands from the repository root.

Python generates ARM JSON; Azure CLI deploys it. This path requires neither Terraform nor Bicep.

For only the Function, use the focused [quick start](function-only.md). For separately owned optional components, see [component deployment](components.md).

## 1. Choose one option

Set `CLI_OPTION` to **one** value from this table:

| Value | Deployment |
|---|---|
| `full` | Everything, including new Front Door and Web App |
| `logo-only` | Function/dependencies + new Front Door/WAF; no Web App |
| `existing-front-door` | Function/dependencies and logo routing on an existing Premium endpoint |
| `function-only` | Function/dependencies; you attach Front Door yourself |

```sh
CLI_OPTION=full
cp "azure-cli/examples/$CLI_OPTION.json" my-demo.json
```

Edit `my-demo.json`:

| Setting | Value to enter |
|---|---|
| `subscription_id` | Your selected Azure subscription ID |
| `name` | Globally unique, 3–18 lowercase letters/digits, starting with a letter; no random suffix is added |
| `location` | Your supported region, for example `westeurope` |
| `publisher_ssh_public_key` | Complete SSH public key from setup |
| `publisher_vm_size` | Optional override if `Standard_B1s` is unavailable |
| `existing_front_door` | Existing-profile option only: profile name, resource group and endpoint name |

Keep the example's `mode` and `publish_artifacts: true`. For existing environments, review [integration and optional reuse inputs](existing-front-door.md). Preserve this config and `.deploy/<name>/manifest.json`; they identify ownership for retries and cleanup. Do not change name, subscription, mode or reused-resource IDs after deployment.

## 2. Render and review

```sh
python3 azure-cli/deploy.py render --config my-demo.json
```

This works offline, builds the Function ZIP and writes `.deploy/<name>/workload.json`. Modes with Front Door also produce `front-door.preview.json`; review both. The edge preview contains placeholder app hostnames; deployment resolves the actual hostnames.

For an Azure workload what-if, create the dedicated empty resource group first. Replace `YOUR_NAME` with the exact `name` in your JSON and use its location:

```sh
az group create --name rg-YOUR_NAME --location westeurope --tags deployment-tool=azure-cli svg-demo-name=YOUR_NAME
python3 azure-cli/deploy.py plan --config my-demo.json
```

If you set an optional `resource_group`, use that name instead. `plan` covers **workload changes only**; review the edge preview separately. `deploy` can create the group itself if you skip what-if. It rejects an existing workload group without the matching ownership tags; do not add these tags to an unrelated group.

## 3. Deploy and connect the private origin

```sh
python3 azure-cli/deploy.py deploy --config my-demo.json
```

The workload and edge use separate incremental ARM deployments. A failure may leave resources: inspect the error and retry with the same config/manifest after correcting it.

**Full / logo-only / existing Front Door:** review the matching requests, then approve:

```sh
python3 azure-cli/deploy.py approve --config my-demo.json
python3 azure-cli/deploy.py approve --config my-demo.json --yes
```

Full mode approves Function and Web App; logo-only and existing-profile modes approve only the Function. The deployment prints `demo_url` and saves it in `.deploy/<name>/manifest.json`. If no matching request exists yet, wait and rerun approval.

**Function only:** skip approval for now. The command prints `function_id`, also saved in the manifest. Read the hostname with the command below, then follow [manual integration](existing-front-door.md#function-only). There is no Front Door URL until you connect it.

```sh
az functionapp show --ids YOUR_FUNCTION_RESOURCE_ID --query defaultHostName -o tsv
```

## 4. Open and test

After Private Link approval and edge propagation, open `demo_url` (`https://YOUR-FRONT-DOOR-HOST/logos/demo`), then run:

```sh
python3 scripts/smoke.py https://YOUR-FRONT-DOOR-HOST
```

Use the hostname **without** `/logos/demo` in this command. See [testing](testing.md) for expected results, reused-catalog flags and troubleshooting. Full mode also serves the Web App at `/`.

## 5. Remove the temporary uploader

```sh
# Show exactly which temporary resources will be removed:
python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json
python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json --yes
```

Then change **`"publish_artifacts": false`** in `my-demo.json` to prevent recreation. Cleanup removes the upload roles, VM/disk, NIC/NSG and any temporary NAT/public IP; the Function and image flow remain running.

**Changing the flag alone does not delete anything.** Incremental ARM deployments retain omitted resources, so run cleanup first. Retained application services continue to incur charges.

## Update the Function later

Change the code, set `publish_artifacts: true`, then repeat deploy, approve if needed, test and uploader cleanup. `deploy` rebuilds the ZIP automatically. Keep the same config/manifest. For an existing private runner, use [manual publishing](deployment.md#private-runner-alternative).

## Delete this installation

There is no automatic whole-environment teardown command. Review `.deploy/<name>/manifest.json` and preserve any needed Storage data first.

1. For **existing Front Door**, remove only the IDs in `edge.route_ids`, then `edge.group_ids` from the shared profile. Removing an origin group also removes its origins. Do not delete the shared profile or endpoint.
2. If `external_reader_role_id` exists, delete that exact role assignment from the reused catalog.

For steps 1–2, use the exact IDs from the manifest (repeat for every listed route/group):

```sh
az resource delete --ids ROUTE_ID_FROM_MANIFEST --api-version 2024-09-01
az resource delete --ids ORIGIN_GROUP_ID_FROM_MANIFEST --api-version 2024-09-01
# Only when external_reader_role_id exists:
az resource delete --ids EXTERNAL_READER_ROLE_ID_FROM_MANIFEST --api-version 2022-04-01
```

3. Delete only the dedicated workload resource group named in `resource_group` after verifying it contains no unrelated resources:

```sh
az group delete --name YOUR_DEDICATED_WORKLOAD_RG --subscription YOUR_SUBSCRIPTION_ID
# When deletion completes, this must print false:
az group exists --name YOUR_DEDICATED_WORKLOAD_RG --subscription YOUR_SUBSCRIPTION_ID
```

In full and logo-only modes, the new Front Door is inside that group and is deleted with it. Reused network, plan and catalog remain outside it. Keep the manifest until all owned resources and external assignments have been removed; never delete a shared resource group.
