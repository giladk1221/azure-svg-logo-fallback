# Azure CLI deployment — no Terraform required

This option uses Python's standard library to generate reviewable ARM JSON and executes it with `az deployment group create`. It uses `az rest` for discovery and post-deployment operations. Neither Terraform, Bicep nor a Python Azure SDK is required.

## 1. Select an option and render offline

```sh
cp azure-cli/examples/full.json my-demo.json
# Alternatives: existing-front-door.json or function-only.json
```

Edit the JSON: select the subscription, a globally unique lowercase `name`, location, and SSH public key. `name` becomes the stable deployment identifier, resource names and `.deploy/<name>/` directory. Replace all example values. Keep the config and manifest; do not change immutable ownership inputs after deployment.

```sh
python3 azure-cli/deploy.py render --config my-demo.json
```

This requires no Azure login. It packages the Function and creates `.deploy/<name>/workload.json` plus a Front Door preview for the modes that use it. Review these files. The preview contains placeholder app hostnames; the deployed edge template uses actual Azure-returned hostnames.

## 2. Authenticate and preview Azure workload changes

```sh
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
# For what-if, first create the dedicated empty workload RG with ownership tags:
az group create -n rg-YOUR_NAME -l westeurope --tags deployment-tool=azure-cli svg-demo-name=YOUR_NAME
python3 azure-cli/deploy.py plan --config my-demo.json
```

`plan` runs Azure what-if for the workload template. Review `front-door.preview.json` separately for the edge changes; edge what-if before the first workload deployment is not performed because the final app hostnames do not yet exist. `deploy` also creates the workload RG if absent. It refuses a workload RG lacking this installation's ownership tags and refuses exact logo-path conflicts on an existing Front Door endpoint.

## 3. Deploy and approve

```sh
python3 azure-cli/deploy.py deploy --config my-demo.json
python3 azure-cli/deploy.py approve --config my-demo.json
# Review the matching connection IDs, then:
python3 azure-cli/deploy.py approve --config my-demo.json --yes
```

The workload and edge use separate **incremental** ARM deployments. Existing Front Door parents are referenced, never redeclared. The CLI saves `.deploy/<name>/manifest.json` with exact owned resources, approval targets and the final `demo_url`. Preserve it for retries and cleanup. A partially completed deployment may leave resources: inspect the deployment error and rerun the same config/manifest after correction.

Function-only skips edge deployment and prints the Function resource ID. Follow [manual Front Door integration](existing-front-door.md#function-only) before testing; it intentionally has no public Function URL.

After Private Link propagation:

```sh
python3 scripts/smoke.py https://YOUR-FRONT-DOOR-HOST
```

For reused catalogs, set `--original` and `--missing`. Check `/` for the Web App in full mode. Existing profile WAF/custom domains/default website routes stay unchanged; logo routes initially use the endpoint's default domain.

## 4. Remove the temporary publisher

```sh
python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json
# Review the exact temporary IDs first:
python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json --yes
```

This removes the publisher's container-scoped upload roles, VM (including its OS disk), NIC/NSG and, if created, its NAT/public IP. It first detaches the NAT from its dedicated subnet. Then set `publish_artifacts=false` in the config to prevent recreation on the next deployment.

**Incremental ARM deployments do not delete resources omitted from a later template.** Merely changing `publish_artifacts` to false is not cleanup; run the cleanup command first. Re-enable publishing for code updates, deploy, verify, and clean up again. For your own private runner, keep publishing disabled and follow the shared manual upload/restart instructions.

## Reuse and full teardown

Optional JSON inputs match Terraform: `existing_network`, `private_dns_zone_ids` (blob), `existing_service_plan_id`, `existing_catalog`, `function_plan_sku`. Their prerequisites are in the deployment chooser. A reused catalog receives only a Function reader assignment; its ID is recorded separately in the manifest for later removal.

There is no automatic whole-environment delete command. Review the manifest first. Remove only its added Front Door route IDs and origin-group IDs from a shared profile, remove the recorded external catalog reader assignment if present, then delete the dedicated workload RG when its data is no longer needed. In full mode the new Front Door profile is inside that RG. Never delete the shared Front Door RG, referenced network, plan or catalog.

Protect the manifest/config and generated templates like deployment state. They contain code and resource metadata, not intended credentials. Do not mix this installation with Terraform ownership, and do not commit `.deploy/` or your private configuration.
