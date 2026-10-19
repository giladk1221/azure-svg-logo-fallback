# Prerequisites and setup

[Back to README](../README.md) · Next: [Terraform](terraform.md) or [Azure CLI](azure-cli.md)

## 1. Have these ready

| Requirement | What you need |
|---|---|
| Azure subscription | Permission to create resources **and assign roles**, including on a reused catalog container; network/private DNS permissions when reusing those resources |
| Region and capacity | Examples use West Europe. Check organizational policy, Linux App Service Basic-or-higher availability and temporary VM quota/capacity |
| Tools | Azure CLI and Python 3.10+. Terraform 1.9–1.x only for the Terraform path. Node.js 22+ only for local application tests |
| Existing Front Door, if selected | **Premium** profile, resource group and endpoint name; review logo path conflicts first |
| Repository access | Git access to this repository; if private, the owner must grant access before a customer can clone it |

The full demo creates a new isolated environment. Use a different checkout/state and deployment name for each installation. Never point both tools at the same resources.

## 2. Clone and select your subscription

Commands use a Bash/zsh-style terminal. Run all subsequent commands from the repository root.

```sh
git clone https://github.com/giladk1221/azure-svg-logo-fallback.git
cd azure-svg-logo-fallback
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
az account show --query '{subscription:id,name:name}' -o table
```

The subscription must allow these resource providers: `Microsoft.Web`, `Microsoft.Storage`, `Microsoft.Network`, `Microsoft.Compute`, `Microsoft.ManagedIdentity`, `Microsoft.Insights`, `Microsoft.OperationalInsights` and `Microsoft.Cdn`. If registration is restricted, ask the subscription administrator to register them. Terraform may attempt provider registration; that can require subscription-level permissions.

## 3. Prepare the private uploader

Default deployment uses a temporary VM to upload the Function ZIP and sample SVGs through private Storage endpoints. It has **no public IP on its NIC** and denies inbound traffic. A temporary NAT gateway supplies outbound VM-agent connectivity in a new network. No SSH login is used, but Azure requires an SSH public key for the VM.

Use an existing SSH **public** key, or create a dedicated one in the ignored deployment directory:

```sh
mkdir -p .deploy
# Run once; do not overwrite a key you already use.
ssh-keygen -t ed25519 -f .deploy/publisher-key -N ''
cat .deploy/publisher-key.pub
```

Paste the complete `.pub` line into `publisher_ssh_public_key` in your selected example. Never paste or commit the private key.

The default upload VM is `Standard_B1s`. If unavailable, set `publisher_vm_size` to an available **x64** size; the acceptance run used `Standard_B2ls_v2` in West Europe. Availability and quota vary by subscription:

```sh
az vm list-skus --location westeurope --resource-type virtualMachines --size Standard_B --all --query '[?length(restrictions)==`0`].name' -o table
```

Keep `publish_artifacts=true` for the first deployment unless using your own [private runner](#private-runner-alternative). The Function cannot run until the package has been uploaded. Both tool guides end with removal of the temporary uploader and its permissions.

## 4. Pick your guide

- [Terraform](terraform.md): state-managed deployment and teardown.
- [Azure CLI](azure-cli.md): Python generates ARM JSON and Azure CLI deploys it; no Terraform, Bicep or Python Azure SDK.

Both tools offer `full`, `existing_front_door` and `function_only`. Defaults create a VNet at `10.84.0.0/16`, separate private host/catalog Storage accounts, a managed identity and monitoring. See [resource reuse](existing-front-door.md#reuse-existing-dependencies) for existing network, plan or catalog prerequisites.

## Private runner alternative

Skip the temporary VM only when you already have a runner with private DNS/network access to the Storage Blob endpoints. Set `publish_artifacts=false` before deployment. Grant the runner **Storage Blob Data Contributor** on the host `packages` container; add that permission on the new catalog's `logos` container only when seeding samples.

After provisioning, run from that private network using the deployed output/manifest values:

```sh
python3 scripts/package.py
python3 scripts/publish.py --host HOST_STORAGE_NAME --package .build/function.zip
# Only for a NEW demo catalog: append --catalog NEW_DEMO_CATALOG_NAME above.
az functionapp restart --resource-group WORKLOAD_RG --name FUNCTION_NAME
az rest --method post --url 'https://management.azure.com/subscriptions/SUBSCRIPTION_ID/resourceGroups/WORKLOAD_RG/providers/Microsoft.Web/sites/FUNCTION_NAME/syncfunctiontriggers?api-version=2024-04-01'
```

The publisher uses Azure CLI credentials, or `--identity` for a VM system identity. It checks private DNS and refuses to overwrite different existing content. Do not seed a customer's existing catalog. Repeat upload/restart/sync after package changes; remove temporary runner permissions when finished.
