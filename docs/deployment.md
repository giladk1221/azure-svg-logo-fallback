# Deploy the demo

## Prerequisites

Use Terraform 1.9+ (below 2.0), Azure CLI, Python 3.10+, and Node.js 22+. The lock file pins provider versions. Azure must support the selected SKUs in your region; the examples use West Europe.

The deploying identity needs resource creation rights, role-assignment rights at the new resources (and at a reused catalog container), and permission to link private DNS to the selected VNet. Register Microsoft.Web, Microsoft.Storage, Microsoft.Network, Microsoft.Compute, Microsoft.ManagedIdentity, Microsoft.Insights, Microsoft.OperationalInsights, Microsoft.ApiManagement and Microsoft.Cdn as applicable. If automatic registration is restricted, have an administrator register the required providers first and configure AzureRM provider registration for your organization.

By default Terraform also creates a single-tenant Entra API application and service principal. The deployer needs permission to create these. To avoid directory creation permissions, supply an existing `backend_application_client_id` with Application ID URI `api://<client-id>` in the same tenant. No client secret is created or required.

Keep Terraform state in an access-controlled backend with locking. The example starts with local state for a sandbox; do not commit state, plans, your `.tfvars`, or credentials. Set up your organization's remote backend before a shared deployment.

## 1. Build and select one installation mode

From the repository root:

```sh
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
npm test
python3 scripts/package.py
cp terraform/examples/full-demo/terraform.tfvars.example terraform/demo.tfvars
# Or: examples/existing-apim or examples/function-only
```

Edit `terraform/demo.tfvars`: replace the subscription, email, names, public SSH key and any resource IDs. The temporary publisher needs an SSH **public** key even though inbound SSH is denied. Generate a dedicated key with `ssh-keygen -t ed25519 -f ~/.ssh/logo-demo`; paste only the `.pub` contents. Never paste a private key.

The `full` mode creates an isolated VNet using `10.84.0.0/16`. Use an unconnected sandbox where this range does not conflict. Existing-network modes require the prerequisites in [existing-apim.md](existing-apim.md).

## 2. Review and apply

```sh
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -var-file=demo.tfvars -out=demo.tfplan
terraform -chdir=terraform apply demo.tfplan
```

The deployment creates private Storage and Function endpoints, assigns identities, and uploads the ZIP from a VM with a private NIC. A NAT gateway provides outbound connectivity for this temporary VM when a new VNet is created; it does not provide inbound access to the VM. Existing networks must already provide outbound connectivity for the VM agent and managed Run Command.

The ZIP name contains its SHA-256 hash. Uploads refuse to overwrite different content. Newly created catalogs receive ACME.svg and CONTOSO.svg; an existing catalog is never seeded or overwritten. The Function restarts and synchronizes triggers after publishing. RBAC/DNS propagation and APIM provisioning can take several minutes. If synchronization fails after upload, rerun apply after inspecting the error; do not enable public Storage as a workaround.

## 3. Complete Front Door private ingress (full demo with Front Door only)

Private Link requires the APIM owner to approve Front Door's managed connection. The initial full deployment leaves APIM public networking enabled for this bootstrap step. A profile-ID header check is installed, but a header alone is spoofable and is **not** the final network security boundary.

```sh
python3 scripts/approve-front-door.py
# Review the listed resource IDs. This only targets the request named by this stack.
python3 scripts/approve-front-door.py --approve
terraform -chdir=terraform output -raw demo_url
```

Wait for Front Door deployment/health propagation. Check the demo and smoke tests through Front Door. Then edit the **same** `demo.tfvars`:

```hcl
lock_apim_public_access = true
```

Plan/apply again. Check Front Door still works and a request directly to the APIM public gateway no longer reaches the logo API. Do not consider a Front Door-only deployment complete before this step. If your tenant/region rejects public-network lockdown, stop and resolve that capability rather than relying only on the header check. The existing-APIM mode never changes shared gateway ingress.

## 4. Verify and remove temporary deployment infrastructure

```sh
terraform -chdir=terraform output
# Use the hostname portion of demo_url, without /logos/demo:
python3 scripts/smoke.py https://YOUR-GATEWAY-OR-FRONT-DOOR-HOST
```

Use `--original EXISTING_KEY --missing KNOWN_ABSENT_KEY` for a reused catalog. Verify an existing image with and without `explicit=true`, a generated image, and the uncached explicit 404. Run the checks again after ingress lockdown.

Edit `publish_artifacts = false` in the same variable file and plan/apply again. This removes the publisher VM, its NIC/NSG, container-scoped upload assignments and, for a new VNet, temporary NAT/public IP. It leaves the Function, package and catalog operational. Review the plan before applying.

## Function-only and existing private runners

Function-only creates no public route. Supply authorized caller **object IDs**, not client IDs. The caller must reach the Function private endpoint and obtain a token for the `backend_audience` output. The [APIM policy template](../terraform/modules/apim-logo-api/policy.xml.tftpl) shows how a gateway calls it. Front Door itself cannot satisfy this APIM managed-identity arrangement; use an authorized application/gateway or adapt authentication deliberately.

For an existing private CI runner, start with `publish_artifacts = false`, apply infrastructure, then run from that runner (Storage must resolve privately):

```sh
python3 scripts/publish.py --host HOST_STORAGE_NAME --package .build/function.zip
# Add --catalog NEW_DEMO_CATALOG_NAME only to seed a newly created demo catalog.
az functionapp restart --resource-group WORKLOAD_RG --name FUNCTION_NAME
az rest --method post --url 'https://management.azure.com/subscriptions/SUBSCRIPTION_ID/resourceGroups/WORKLOAD_RG/providers/Microsoft.Web/sites/FUNCTION_NAME/syncfunctiontriggers?api-version=2024-04-01'
```

The runner identity needs Blob Data Contributor on the `packages` container and, only when seeding, the new `logos` container. With `--identity`, the script uses a VM's system identity instead of Azure CLI. The Function cannot start the packaged application before the first upload. Repeat restart/sync after code updates. For direct private smoke tests, supply `LOGO_TEST_TOKEN` in the environment; never put tokens into a command argument or repository file.

## Code updates and teardown

Rebuild the ZIP, temporarily enable the publisher, and plan/apply using the same state and inputs. Verify, then remove the publisher again. Package hashes preserve previous ZIPs; add a reviewed retention policy for long-lived deployments. Do not change deployment mode in place; use a separate state for a new installation.

`terraform -chdir=terraform destroy -var-file=demo.tfvars` deletes the demo, including newly created Storage data. In existing-APIM mode it removes the APIs this stack created, the Function and its supporting resources, and added role assignments/DNS links; it does not delete the referenced APIM, VNet, plan, catalog, or Entra application. Review the destroy plan and preserve any data you need first.
