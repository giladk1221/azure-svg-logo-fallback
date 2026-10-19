# Security and operations

[Back to README](../README.md) · [Testing and troubleshooting](testing.md)

## Private access and permissions

Front Door Premium reaches the Function and full-demo Web App using approved managed Private Link connections (`sites`). Both apps have public network access disabled from creation. The apps serve public demo content over those connections; the Function uses an anonymous HTTP trigger. No gateway token, app-registration secret, Function key or SAS is required. Approve only intended private endpoint requests. A private endpoint connection is not end-user authentication.

The Function integrates with the VNet for outbound access to private Blob Storage. Its user-assigned identity has Blob Data Reader only on the logo container, and Blob Data Owner on separate host Storage for runtime operations and package access. No unused Queue/Table endpoints or permissions are added. New accounts disable shared-key access, public containers and public network access.

## Temporary uploader

The optional publisher's system identity has Blob Data Contributor only on the package container and new sample-logo container. It has no public NIC address, denies inbound traffic and uses managed Run Command. A temporary NAT/public IP provides outbound VM agent connectivity for a new network. It is not in the request flow and should be removed after verification. Existing catalogs are never seeded by the publisher.

## Monitoring and production boundaries

The full demo creates a WAF managed ruleset in Prevention mode. Existing-profile mode leaves the owner's WAF unchanged. Configure diagnostics and alerts for unhealthy origins, 5xx, dependency latency and cost in the customer's monitoring environment. App Insights/Log Analytics are created with 30-day retention; edge diagnostic export and production alerting are not configured by this demo.

Stored SVGs are trusted administrator-uploaded assets. There is no public upload API or SVG sanitizer. Function logs describe origin executions; cached Front Door hits do not invoke the Function. Health probes check Function availability, not catalog readiness. The small Web App source is embedded in its startup configuration for this demo; it is not a production application deployment pipeline.

## Deployment ownership and state

Use protected Terraform state or CLI config/manifests and separate installations per tool. AzureRM can retain Storage access keys in state even when shared-key authentication is disabled; treat state and saved plan JSON as sensitive. The CLI's ARM deployments are incremental: absent resources are not automatically deleted. No workflow logs into Azure or applies resources automatically. Cost, availability and production hardening remain deployment-specific.

References: [Function host identity permissions](https://learn.microsoft.com/azure/azure-functions/manage-connections), [run-from-package identity](https://learn.microsoft.com/azure/azure-functions/run-functions-from-deployment-package), [Front Door private app origins](https://learn.microsoft.com/azure/frontdoor/standard-premium/how-to-enable-private-link-web-app).

## Platform-managed settings

Terraform preserves externally managed Storage resource-access entries (`network_rules.private_link_access`), such as entries added by a subscription Defender policy. It still manages public access as disabled, default firewall action as deny, and trusted-service bypass as none. Review such policy-managed entries through your subscription security controls; publisher cleanup must not remove them.

The temporary publisher preserves Azure-assigned IP tags on its egress address to avoid unnecessary replacement on subsequent plans. The Web App keeps filesystem container logs for three days (100 MB limit) to make startup failures diagnosable. Its shared startup command decodes the embedded source into an ephemeral file and runs Node directly, avoiding nested JavaScript quoting in App Service startup configuration.
