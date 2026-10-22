# Deploy the parts you need

[Back to README](../README.md) · [Function-only quick start](function-only.md)

The **Function and its required dependencies form one working unit**. The sample
website is optional. Front Door is optional infrastructure that connects to an
existing Function; it needs an origin to serve traffic. **No option deploys APIM.**

## Choose a working combination

| What you need | Entry point | Creates / connects |
|---|---|---|
| Just the Function service | [`function_only` quick start](function-only.md) | Function + runtime/Storage/identity/networking/monitoring; no edge or website |
| Only publish code into a prepared app | [Code-only publishing](function-only.md#publish-code-only-to-an-existing-function-app) | No new infrastructure |
| Logo demo with a public URL | `logo_only` via [CLI](azure-cli.md) or [Terraform](terraform.md) | Function unit + Front Door Premium/WAF; no sample website |
| New Function on an existing Front Door | `existing_front_door` via [CLI](azure-cli.md) or [Terraform](terraform.md) | New Function unit + logo routes on the supplied Premium endpoint |
| Add edge integration to an already deployed Function | [Standalone Front Door stack](#add-front-door-to-an-existing-function) | New Premium edge/WAF or routes on an existing endpoint; references the existing Function |
| Only the optional website | [Standalone Web App stack](#optional-demo-website) | Private website + its own plan, or reuses a plan; no Function, Storage or Front Door |
| Complete demo | `full` via [CLI](azure-cli.md) or [Terraform](terraform.md) | Function unit + Front Door Premium/WAF + website, wired together |

The four combined modes are available in **both** deployment tools. The two
standalone stacks use **Terraform** and reuse the same modules as the full demo.
Existing network, logo catalog and compatible plan can be reused in any combined
mode; see [reuse prerequisites](existing-front-door.md#reuse-existing-dependencies).
We do not offer a disconnected “Storage-only” or “identity-only” demo: these are
configured dependencies of the Function.

## Function + Front Door without the website

This is the smallest complete public logo demo. The Function already serves its own
interactive page at `/logos/demo`; a Web App is unnecessary for testing SVG behavior.

Choose **one** tool, then follow its normal deploy/approve/test/cleanup steps:

```sh
# Azure CLI: edit placeholders, then follow docs/azure-cli.md from step 2.
cp azure-cli/examples/logo-only.json my-demo.json

# OR Terraform: edit placeholders, then follow docs/terraform.md from step 2.
cp terraform/examples/logo-only/terraform.tfvars.example terraform/demo.tfvars
```

There is no website at `/`; use `/logos/demo`. The existing `full` mode still deploys
both the website at `/` and the logo demo at `/logos/demo`.

## Build up a demo without redeploying its existing parts

For a new installation that will grow in stages:

1. Deploy `function_only` using the quick start. Keep its config and state/manifest.
2. Deploy the separate edge stack below, passing the Function's exact ID/hostname.
3. Optionally deploy the separate website and add its ID/hostname to that same edge
   stack. The existing logo route keeps pointing to the same Function.

Each stack owns different resources. Copying outputs as inputs does not transfer
ownership. Keep IDs/hostnames current if an origin is intentionally replaced.
**Do not change an existing full deployment to `function_only` to split it up**:
Terraform could remove its edge and website, and CLI refuses mode changes. Leave
existing full demos managed together; use these separate roots for newly added
components. Do not import/redeclare an app or route already owned by another stack.

## Optional demo website

From the repository root, with Azure CLI login and Terraform installed:

```sh
cp terraform/standalone/webapp/demo.tfvars.example terraform/standalone/webapp/demo.tfvars
```

Edit `subscription_id`, a globally unique `name`, and `location`. By default it gets
its own Linux B1 plan, so it does not depend on the Function's plan. To reuse a
compatible same-region plan, set `existing_service_plan_id`; that creates a
lifecycle dependency on that external plan.

```sh
terraform -chdir=terraform/standalone/webapp init
terraform -chdir=terraform/standalone/webapp plan -var-file=demo.tfvars -out=demo.tfplan
terraform -chdir=terraform/standalone/webapp apply demo.tfplan
terraform -chdir=terraform/standalone/webapp output
```

The Web App stays private. Deploying it alone provisions the website, but public
access requires the Front Door connection below (or customer-managed private
inbound connectivity). Its logo link works only after a Function route is connected.
No uploader, SSH key, Function ZIP, Storage or catalog is needed for this stack.

## Add Front Door to an existing Function

Use this when the Function **already exists**, including one deployed by the CLI.
Unlike `existing_front_door` combined mode, this stack does not create another Function.

```sh
cp terraform/standalone/front-door/demo.tfvars.example terraform/standalone/front-door/demo.tfvars
```

Set `subscription_id`, a globally unique `name`, `location`, `function_id` and
`function_hostname`. Take the last two from the Function's Terraform outputs or
CLI manifest/Azure lookup; use the actual hostname, not a constructed name or URL.
The origins must support Front Door Premium Private Link to `sites` and the selected
Private Link region.

- Leave `existing_front_door` unset to create a new Premium profile, endpoint and WAF.
- Supply `existing_front_door` to add routes on an existing Premium endpoint.
  Review [integration requirements](existing-front-door.md#existing-front-door)
  first. This Terraform stack does not automatically detect route conflicts.
- Leave `webapp` unset for just logos. To connect the standalone website, set
  `webapp = { id = "...", hostname = "..." }` using its outputs. This adds `/*`;
  do not add it to a shared endpoint already serving another website/default route.

```sh
terraform -chdir=terraform/standalone/front-door init
terraform -chdir=terraform/standalone/front-door plan -var-file=demo.tfvars -out=demo.tfplan
terraform -chdir=terraform/standalone/front-door apply demo.tfplan
python3 scripts/approve-front-door.py --terraform-dir terraform/standalone/front-door
# Review the matching requests, then:
python3 scripts/approve-front-door.py --terraform-dir terraform/standalone/front-door --approve
terraform -chdir=terraform/standalone/front-door output -raw demo_url
```

Open the printed `/logos/demo` URL after propagation. Run the [smoke checks](testing.md)
against its hostname. With `webapp` set, `/` must serve the website and `/logos/*`
must still serve the Function. Verify both before removing or replacing any old route.
To add the website later, edit only this stack's `webapp` input, plan/apply again,
approve the new website connection and repeat these checks.

This uses the same `/logos/*` paths, query-string caching, health probes, private
origin and certificate settings as the full demo. Existing profile/endpoint/WAF and
custom domains remain with their owner; customer domain associations are not automatic.

## Ownership, cleanup and validation

Use each standalone directory's **own Terraform state**. Save its `.tfvars` and
state securely; use a remote backend with locking for team work. Do not use
`terraform -target` to turn the full demo into separately owned components.
Keep a separate checkout or backend/state key for each additional installation.

To remove a standalone component, review a destroy plan from its own directory:

```sh
# Example: remove ONLY the separate edge stack.
terraform -chdir=terraform/standalone/front-door plan -destroy -var-file=demo.tfvars -out=destroy.tfplan
terraform -chdir=terraform/standalone/front-door apply destroy.tfplan
```

Removing edge leaves the origin apps/Storage intact, but stops traffic through the
removed routes. Before removing a website, remove its optional `webapp` input from
its edge stack and apply that change. Remove edge routes before deleting their
Function origin. Do not delete a reused plan while any app still uses it. New plans
and Front Door Premium remain billable until removed.

The new `logo_only` mode and standalone roots have offline template/mocked-plan
checks. They have not been deployed to Azure as part of this change. See the
[validation record](validation.md) for the prior full-demo live acceptance runs.
