# Choose the deployment method and scope

| Scope | Terraform example | Azure CLI example |
|---|---|---|
| Full demo | [full-demo](../terraform/examples/full-demo/terraform.tfvars.example) | [full.json](../azure-cli/examples/full.json) |
| Existing Front Door Premium | [existing-front-door](../terraform/examples/existing-front-door/terraform.tfvars.example) | [existing-front-door.json](../azure-cli/examples/existing-front-door.json) |
| Function and dependencies only | [function-only](../terraform/examples/function-only/terraform.tfvars.example) | [function-only.json](../azure-cli/examples/function-only.json) |

Use one method per installation. Both deploy the same Function package and fictional assets. Terraform manages resource lifecycle through state. The CLI path uses incremental ARM deployments and an ownership manifest, with explicit temporary-resource cleanup; it does not run Terraform.

## Prerequisites

Azure public cloud; a subscription/region supporting Front Door Premium Private Link, Linux App Service Basic or higher, and the optional B1s publisher VM. Examples use West Europe. Verify SKU availability, quotas, regional Private Link support and organizational policy before applying.

Install Azure CLI, Python 3.10+ and Node.js 22+. Add Terraform 1.9+ (below 2.0) only for that deployment method. No Entra application registration, gateway subscription keys or Function secrets are needed.

The deployer needs resource creation rights and role-assignment rights on new resources and any reused catalog container, plus private DNS/VNet link rights. Register Microsoft.Web, Microsoft.Storage, Microsoft.Network, Microsoft.Compute, Microsoft.ManagedIdentity, Microsoft.Insights, Microsoft.OperationalInsights and Microsoft.Cdn as applicable. Terraform provider registration may require subscription-level rights; use your organization's pre-registration process when those are restricted.

The new VNet uses `10.84.0.0/16`; use an isolated demo without address overlap, or supply an existing network. A reused Function integration subnet must be delegated to `Microsoft.Web/serverFarms`; private endpoints need a separate nondelegated subnet. A reused publisher subnet must support VM agent/Run Command outbound connectivity. Reused Blob DNS zones must already be linked or forwarded to the Function and publisher network. A reused logo account must already have private Blob connectivity.

## Private package publishing

By default, a temporary B1s VM with no public NIC address uploads the ZIP and sample SVGs through private Blob endpoints. New networks also get a temporary NAT gateway/public IP for outbound VM-agent connectivity; this is not an inbound VM endpoint. Inbound traffic to the VM is denied. Supply an SSH **public** key because the Linux VM API requires it; no SSH connection is used. Never commit private keys.

The Function uses a user-assigned identity for package/host Storage and a container-scoped reader role for logo Storage. A separate host account prevents runtime write permissions from granting writes to the logo catalog. The HTTP-only Function needs no Queue/Table endpoints or trigger permissions. No public Storage exception, shared account key or SAS is used.

New catalogs receive ACME.svg and CONTOSO.svg. Existing catalogs are not seeded or overwritten. For deployment from your own private runner, set `publish_artifacts=false` and use [manual publishing](terraform.md#private-runner-alternative), then restart/synchronize the Function. It cannot start the packaged code before the first upload.

## After either deployment

1. Review and approve only this deployment's pending Front Door managed Private Link connections on the Function (and Web App in full mode). Both apps keep public network access disabled throughout.
2. Wait for origin/route propagation and run the smoke script through Front Door.
3. Confirm the Web App homepage in full mode, stored SVGs, normal generated SVGs and the missing+explicit 404. Direct public access to the apps and Storage must remain blocked.
4. Remove the temporary publisher through the chosen tool's documented cleanup process.

These are public image/demo endpoints through Front Door; there is no end-user authentication. Only approve intended private endpoint requests. Do not enable Easy Auth requiring a bearer token for this direct Front Door flow unless you also redesign how the origin is authenticated.
