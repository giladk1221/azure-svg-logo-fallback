# Existing Front Door and Function-only integration

[Back to README](../README.md) · [Terraform steps](terraform.md) · [Azure CLI steps](azure-cli.md)

## Existing Front Door

Use `existing_front_door` when you want this deployment to add the integration automatically. Supply the **Premium** profile name, its resource group and endpoint name in the chosen example. Neither tool imports or redeclares those parents.

The deployment adds a uniquely named logo origin group, Function origin and route. It creates no Web App or replacement default route. Existing WAF, other origins, rule sets and custom domains remain in their owning configuration.

Before applying:

1. Inspect the endpoint's routes. This deployment uses `/logos/*` and `/static/v2/static/logos/*` on the default `azurefd.net` hostname. A default `/*` route can coexist; an exact logo-path conflict needs a deliberate migration. Also inspect narrower overlaps and rewrites. CLI checks exact conflicts; Terraform users must review them before apply.
2. Ensure no other stack manages these new child resources. Do not deploy over the original demo's current logo route; use a separate endpoint for evaluation.
3. Confirm your permissions include adding edge child resources and approving the Function's private connection.
4. Deploy, approve and test using your selected tool's guide.

**Custom domains are not associated automatically.** Test the default endpoint first, then let the existing Front Door configuration owner associate the required custom domain with the logo route and verify its WAF coverage. This repository does not change customer DNS.

## Function-only

Use `function_only` when the customer's existing infrastructure code will own the Front Door integration. This creates the Function and its dependencies, with **no** Front Door profile, endpoint, route or Web App.

After deploying, get `function_id` and the actual Function hostname from Terraform outputs or the CLI manifest/Azure lookup described in your tool guide. In the Azure portal, open the existing **Front Door Premium** profile and its **Front Door manager**, or apply the equivalent settings through its owning infrastructure stack.

### 1. Add an origin group and origin

| Setting | Value |
|---|---|
| Origin group name | A new, unique name such as `company-logos` |
| Health probe | Enabled; HTTPS, **HEAD**, `/logos/health`, 60-second interval |
| Session affinity | Disabled |
| Origin type/resource | App Services; select the deployed Function App |
| Origin hostname | The exact Azure-provided Function hostname |
| Origin Host header | The same Function hostname |
| HTTPS port / certificate validation | `443` / enabled |
| Private Link | Enabled; target the Function resource ID, subresource **`sites`** |
| Private Link location | A supported Front Door Private Link region near the Function; examples use West Europe |
| Request message | A unique, recognizable message identifying this integration |

Front Door creates its managed private endpoint in Microsoft's network. Do not use the Function's VNet integration subnet as the Front Door endpoint location; VNet integration is for the Function's outbound Storage access.

### 2. Approve that private connection

Open **Function App → Networking → Private endpoints**, locate the pending connection with your request message and approve only that connection. Wait until its state is **Approved**. Leave Function public network access disabled. The repository approval helpers only know origins created by the repository; manually created origins need approval here or in the owning stack.

### 3. Add a logo route to the endpoint

| Setting | Value |
|---|---|
| Domains | Start with the default endpoint hostname; associate a customer domain separately when ready |
| Patterns | `/logos/*` and, if needed, `/static/v2/static/logos/*` |
| Origin group | The group just created |
| Origin path / rewrite | Leave origin path empty; preserve the requested path |
| Client protocols | HTTP and HTTPS with HTTP-to-HTTPS redirect enabled |
| Forwarding protocol | HTTPS only |
| Caching | Enabled; respect the Function's `Cache-Control` headers |
| Query-string caching | **Use Query String** (`UseQueryString`); forward all query parameters |
| Compression | Optional; repository routes enable it for SVG/HTML |

Do not discard `explicit`, normalize its value, or override `no-store`. Otherwise a cached normal placeholder could incorrectly answer an original-only request. Review associated rule sets for overrides. Confirm existing WAF protection covers the selected domain.

### 4. Verify

After propagation, open `https://YOUR-FRONT-DOOR-HOST/logos/demo` and follow [the testing guide](testing.md). No Function key or bearer token is required: the HTTP trigger is anonymous for public logo delivery through the approved private origin. Private Link restricts origin access; it is not end-user authentication.

## Reuse existing dependencies

These inputs are optional in **both tools**. Leaving them unset creates new dependencies in the dedicated workload group. Use the Terraform variable names below, or the same names as JSON properties for CLI.

| Input | Required properties / prerequisites |
|---|---|
| `existing_service_plan_id` | Full ARM ID of a compatible Linux App Service plan, Basic or higher, in the workload region with sufficient capacity |
| `existing_catalog` | `account_id`, `account_name`, `container_name`; existing private Blob connectivity and DNS reachable from the Function network. No sample uploads or new catalog private endpoint are created |
| `existing_network` | `vnet_id`, `function_subnet_id`, `private_endpoint_subnet_id`; also `publisher_subnet_id` when using the temporary uploader |
| `private_dns_zone_ids` | `{ blob = "ZONE_RESOURCE_ID" }` in Terraform, or `{ "blob": "ZONE_RESOURCE_ID" }` in JSON; the Blob zone must already be linked/forwarded to the workload networks |

The Function integration subnet must be delegated to `Microsoft.Web/serverFarms`. Use a separate nondelegated private-endpoint subnet. A reused publisher subnet needs working outbound VM-agent/Run Command connectivity; this deployment does not add a NAT gateway to a reused network. Do not introduce an overlapping default `10.84.0.0/16` network into a connected environment.

Even when reusing all optional resources, the deployment creates private **host Storage**, Function managed identity and monitoring. It adds a container-scoped Blob Data Reader assignment to the reused logo catalog. It does not grant catalog write access to the Function. Keep referenced resources outside the dedicated workload group so teardown cannot delete them with that group.

References: [Front Door Private Link to Web Apps and Functions](https://learn.microsoft.com/azure/frontdoor/standard-premium/how-to-enable-private-link-web-app), [App Service private endpoints](https://learn.microsoft.com/azure/app-service/overview-private-endpoint).
