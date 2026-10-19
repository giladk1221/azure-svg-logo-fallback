# Validation scope

GitHub Actions runs Function/Web App behavior tests, deterministic packaging/private-publisher tests, Azure CLI template and ownership tests, Terraform provider validation and mocked plans for the three deployment modes. These checks need no Azure credentials and create no Azure resources.

On **2026-10-19**, the **full** mode was deployed and tested in two isolated West Europe environments: one created with Terraform and one with Azure CLI/ARM. Both passed the 23-check HTTP acceptance suite. The existing demo was preserved; its resource inventory was unchanged, its activity log showed no writes/deletions during the test, and its demo page continued returning HTTP 200.

| Live check | Terraform | Azure CLI |
|---|---|---|
| Private Web App at `/`, Function demo and health routes | Pass | Pass |
| ACME/CONTOSO original SVG bytes match stored fixtures | Pass | Pass |
| Missing JEMXX generates `JE` SVG, HTTP 200 | Pass | Pass |
| Missing + `explicit=true`: 404/no-store; existing + explicit: original 200 | Pass | Pass |
| Legacy path and forced-fallback path | Pass | Pass |
| Real `TCP_HIT` for originals and generated SVGs; query variants stay separate | Pass | Pass |
| Direct public Function, Web App and both Storage endpoints return 403 | Pass | Pass |
| Public access disabled; approved Private Link; HTTPS certificate validation | Pass | Pass |
| Function identity scoped to host Storage and catalog container | Pass | Pass |
| Original/missing/generated/suppressed events in Application Insights | Pass | Pass |
| Publisher roles, VM/disk, NIC/NSG and NAT/IP removed | Pass | Pass |
| Full 23-check suite repeated after publisher cleanup | Pass | Pass |

The local regression suite contains **46 passing checks**: 18 Node tests, 18 Python tests and 10 Terraform mocked scenarios.

The run exposed and corrected regional upload-VM availability, App Service startup quoting, asynchronous Private Link approval handling, scoped-role cleanup API selection, and Terraform drift from platform/policy-managed properties. New templates include those fixes. The Function application logic did not need changes.

This run tested **full mode with both tools**. Existing-Front-Door and Function-only modes have configuration/mocked-plan coverage, but were not separately deployed in this acceptance run. Customer DNS/custom domains, load/failover testing, live catalog-outage injection and new-original replacement after TTL expiry remain outside this result. Mocked plans alone do not prove cloud behavior, and Azure CLI `plan` is a workload what-if rather than a live traffic test.

## Acceptance checks for each deployment method

1. Full demo: deploy, approve the Function and Web App Private Link requests, run smoke checks through Front Door, and confirm `/` comes from the Web App while `/logos/demo` comes from the Function.
2. Existing Front Door: verify Premium tier, inspect path conflicts, deploy only the added logo resources, approve the connection, and confirm existing routes/WAF remain intact.
3. Function only: connect the output Function to a Premium private origin in the owning stack, approve it, then test through Front Door. A public Function URL is intentionally inaccessible.
4. In every mode, confirm existing+explicit=200, missing=generated SVG 200, missing+explicit=404/no-store, and no mixing across cache keys. Direct public app/Storage access must remain blocked.
5. Add a new original for a previously missing symbol and verify replacement after TTL expiry or a scoped purge.
6. In an isolated sandbox, verify catalog failures give 502/no-store rather than a generated placeholder. Do not inject failures into a shared customer catalog.
7. Verify Function events in App Insights and remove temporary publisher infrastructure using the chosen tool's cleanup process.

Sample images are fictional. Exact Fastly color parity is not part of the validation claim.

## Repeat the full-demo HTTP acceptance checks

For a fresh catalog seeded with this repository's ACME/CONTOSO fixtures:

```sh
python3 scripts/acceptance.py https://YOUR-FRONT-DOOR-HOST \
  --function-host YOUR-FUNCTION.azurewebsites.net \
  --webapp-host YOUR-WEBAPP.azurewebsites.net \
  --storage-account YOUR_HOST_STORAGE \
  --storage-account YOUR_LOGO_STORAGE
```

This read-only check verifies the Web App and Function routes, byte-for-byte original SVGs, generated `JE`, both `explicit=true` cases, the legacy and forced-fallback paths, real Front Door cache hits for originals and generated images, and direct public-origin rejection. It uses fresh query keys for each run and repeats query variants to detect cache contamination. It requires a cache hit, unlike the shorter smoke helper. It does not upload files, change access rules or purge caches.

Keep control-plane evidence separately: public access disabled, private connections approved, HTTPS/certificate validation enabled, least-privilege managed identity roles, and temporary publisher removal. An anonymous Storage 403 alone does not prove private networking; verify both settings and traffic.
