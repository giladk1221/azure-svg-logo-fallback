# Security and operations

APIM uses its system-assigned managed identity to get a token for the Function's single-tenant Entra API audience. Function Easy Auth requires that audience and allows only the configured caller object IDs. The HTTP trigger is `anonymous` because Easy Auth enforces authentication before the trigger; no Function keys are distributed.

The Function has public network access disabled, an inbound private endpoint and outbound VNet integration. Its user-assigned identity reads only the configured logo container. Separate private host Storage holds runtime state and immutable code packages. Host Storage identity permissions are separate from catalog read permissions. This HTTP-only app uses Storage Blob Data Owner for host storage; it does not add queue/table endpoints or data permissions for triggers it does not use. Shared account keys and public containers are disabled on new accounts. Package download uses the Function identity, without SAS.

The optional publisher identity receives Blob Data Contributor only on the package container and, for new catalogs, the logo container. It runs through Azure managed Run Command, has no public NIC address and denies inbound traffic. Its outbound NAT address is not an inbound VM endpoint. Remove it after deployment. The script verifies private Storage DNS and refuses to overwrite different existing files.

The new full APIM remains a public image gateway if Front Door is disabled. With Front Door enabled, approve Private Link and then disable APIM public access using the documented second apply. The Front Door profile-ID check is defense in depth, not a substitute for that network restriction. The new Front Door profile uses a managed WAF ruleset in Prevention mode; tune false positives before production. This demo does not add rate-limit policy to a shared gateway or provision customer DNS/certificates.

App Insights and Log Analytics are created with 30-day retention. Use Function traces for fallback events and configure Azure Monitor alerts for 5xx, dependency latency, unhealthy origins and cost. Front Door/APIM diagnostic export and per-request auditing are not configured by this demo. Add them to your organization's monitoring destination. Browser network tools show the public gateway request; Storage can only be browsed from an authorized private network with appropriate Blob data permissions.

Treat state as sensitive even though no runtime secrets are intentionally generated: provider state may contain service configuration and monitoring connection information. Use separate environments, protected state access and a reviewed deployment identity. GitHub validation CI does not log into Azure or deploy resources.

References: [Function run from package](https://learn.microsoft.com/azure/azure-functions/run-functions-from-deployment-package), [App Service Entra authentication](https://learn.microsoft.com/azure/app-service/configure-authentication-provider-aad), [Front Door to APIM Private Link](https://learn.microsoft.com/azure/frontdoor/standard-premium/how-to-enable-private-link-apim).

Host identity reference: [AzureWebJobsStorage minimum permissions](https://learn.microsoft.com/azure/azure-functions/manage-connections).
