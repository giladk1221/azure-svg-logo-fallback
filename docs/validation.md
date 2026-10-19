# Validation scope

GitHub Actions runs Function/Web App behavior tests, deterministic packaging/private-publisher tests, Azure CLI template and ownership tests, Terraform provider validation and mocked plans for the three deployment modes. These checks need no Azure credentials and create no Azure resources.

Neither the revised Terraform architecture nor the Azure CLI templates have completed an Azure end-to-end acceptance deployment. Mocked plans and offline ARM inspection do not verify regional capacity, tenant policy, private DNS, package startup, Private Link approval or edge propagation. Azure CLI `plan` adds a real workload what-if in the target subscription but is not a live traffic test.

## Acceptance checks for each deployment method

1. Full demo: deploy, approve the Function and Web App Private Link requests, run smoke checks through Front Door, and confirm `/` comes from the Web App while `/logos/demo` comes from the Function.
2. Existing Front Door: verify Premium tier, inspect path conflicts, deploy only the added logo resources, approve the connection, and confirm existing routes/WAF remain intact.
3. Function only: connect the output Function to a Premium private origin in the owning stack, approve it, then test through Front Door. A public Function URL is intentionally inaccessible.
4. In every mode, confirm existing+explicit=200, missing=generated SVG 200, missing+explicit=404/no-store, and no mixing across cache keys. Direct public app/Storage access must remain blocked.
5. Add a new original for a previously missing symbol and verify replacement after TTL expiry or a scoped purge.
6. In an isolated sandbox, verify catalog failures give 502/no-store rather than a generated placeholder. Do not inject failures into a shared customer catalog.
7. Verify Function events in App Insights and remove temporary publisher infrastructure using the chosen tool's cleanup process.

Sample images are fictional. Exact Fastly color parity is not part of the validation claim.
