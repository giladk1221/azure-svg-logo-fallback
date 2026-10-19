# Integrating an existing APIM

The existing-APIM example reads the service as a Terraform data source. It adds two new APIs (`<prefix>-logos-logos` and `<prefix>-logos-legacy`) with GET/HEAD operations and API-scoped policies. It does not import the APIM service into this state, change its SKU, enable its identity, attach its network, or alter other APIs.

## Required before apply

- An APIM tier/network configuration that can reach private backends. This demo targets Standard v2 with outbound VNet integration; a suitably configured supported classic tier can also be adapted. A public-only APIM or an inbound private endpoint by itself does not provide outbound VNet connectivity.
- A system-assigned APIM managed identity. Its object ID becomes the Function's allowed caller. This example does not select a user-assigned APIM identity.
- A reachable VNet and a dedicated Function integration subnet delegated to `Microsoft.Web/serverFarms`, plus a nondelegated private-endpoint subnet. Reused plan/subnets must meet Azure's subnet-sharing and capacity requirements. The Function plan must be Linux Dedicated, Basic or higher, in the chosen region.
- A separate publisher subnet with VM-agent outbound connectivity if using the optional publisher. The stack applies an NSG to its new NIC, not the existing subnet, and does not attach a NAT gateway to a reused network.
- Private DNS resolving Function and Blob endpoints from **both** APIM and the Function. With custom DNS, configure forwarding. If APIM is in a peered VNet, link/forward the relevant zones to that VNet too. Supplying existing zone IDs does not create or change their links.
- Unused `/logos` and `/static/v2/static/logos` API paths. Do not deploy over an existing customer API; choose a separate gateway or review path changes first. Existing inherited global/product policies may still enforce authorization, rewrite URLs or cache responses; review these with the gateway owner.

The root checks for a system identity and a non-`None` VNet configuration. This catches an unconfigured public-only gateway, but it cannot prove reachability, DNS, routes or global policy compatibility. Preview SKUs may not be represented by the provider; use a supported gateway configuration rather than assuming a preview AI gateway is interchangeable.

## What remains under the gateway owner's control

Existing public/private ingress, custom domain certificates, subscription requirements, WAF, throttling, global policies and any Front Door routing remain in the APIM owner's stack. New logo APIs have `subscription_required=false` for public image delivery, while the private Function requires the gateway identity. If customer images require user authorization, design that at the gateway and disable shared caching accordingly.

An existing Front Door route should target the APIM gateway, preserve paths and query parameters, use HTTPS, and keep query strings in the cache key. Use Private Link where supported, and restrict shared gateway ingress without breaking its other APIs. Do not route directly to Blob Storage expecting Front Door to invoke the Function on a 404.

## Reusing an existing logo container

Set `existing_catalog` to its account ID, account name and container. The stack assigns the Function identity `Storage Blob Data Reader` scoped to that container. It does not create that account's private endpoint, change firewall rules, upload samples, or change data. Ensure private DNS/connectivity already works. Upload stored logos as `image/svg+xml`; blob names are case-sensitive and are looked up exactly as requested.

The supplied demo page names ACME/CONTOSO. For a reused catalog, replace those cards with keys that actually exist, or run the smoke script with `--original` and `--missing`.

References: [APIM outbound integration](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound), [APIM private endpoints](https://learn.microsoft.com/azure/api-management/private-endpoint), [managed-identity policy](https://learn.microsoft.com/azure/api-management/authentication-managed-identity-policy).
