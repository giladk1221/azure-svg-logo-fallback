# Existing Front Door and Function-only integration

## Existing Front Door

Provide a **Premium** profile name, its resource group, and endpoint name. Terraform reads them as data sources; CLI references their ARM IDs. Neither path imports or redeclares those parent resources. The new resources are a uniquely named logo origin group, Function origin and route. No Web App or replacement default route is created in this mode. Existing WAF, other origins, rule sets and custom domains remain in their owning configuration.

Review existing routes first. The new route owns `/logos/*` and `/static/v2/static/logos/*` on the endpoint's default hostname. A default `/*` route can coexist because these are more specific, but exact conflicting logo paths must be migrated deliberately. The CLI checks exact conflicts; Terraform users must check before apply. Review narrower overlapping paths and rule-set rewrites as well. Do not let another Terraform stack manage the same child resources.

The Function origin uses HTTPS, certificate-name validation, its Azure-provided hostname as the origin Host header, and Private Link subresource **`sites`**. Approve only this deployment's pending connection on the Function. Function public network access stays disabled. The Function's VNet integration is for outbound private Storage access; Front Door's managed private endpoint is in Microsoft's managed network, not in your integration subnet.

The added route keeps the query string in the cache key and forwards it intact. Otherwise a normal cached placeholder could incorrectly answer `explicit=true`. The route does not attach existing custom domains automatically; after testing the default hostname, the owning stack can associate the required domain and migrate route ownership deliberately.

If the logo path already points to your current demo Function, do not run a second stack over it. Keep the old route until you have prepared a deliberate route update or use a separate test endpoint. This repository does not import or mutate your existing live demo automatically.

## Function-only

This mode creates no Front Door profile, endpoint, route or Web App. Reuse compatible network, Linux plan and private catalog inputs to minimize new components. A private host Storage account and user-assigned Function identity are still needed for the runtime/package.

After deployment, use the Function resource ID/hostname outputs to configure the existing Front Door Premium in its owning stack:

1. New origin group with `HEAD /logos/health` over HTTPS.
2. Origin hostname and origin Host header: the Function's actual Azure hostname; certificate validation enabled.
3. Enable Private Link to the Function resource ID, subresource `sites`, using a supported region near the Function.
4. Approve that exact managed private endpoint connection on the Function.
5. Route `/logos/*` and the optional legacy alias to the group, HTTPS only to the origin, query strings included in the cache key.
6. Open `/logos/demo` and run the smoke script. Do not enable the Function's public network access as a shortcut.

The Function's HTTP trigger is anonymous for public logo delivery through the approved private connection. Front Door does not supply an application bearer token in this configuration. Private access is the origin boundary; only trusted administrators may approve new private endpoints. End-user authentication is outside this demo.

References: [Front Door Private Link to Web Apps and Functions](https://learn.microsoft.com/azure/frontdoor/standard-premium/how-to-enable-private-link-web-app), [App Service private endpoints](https://learn.microsoft.com/azure/app-service/overview-private-endpoint).
