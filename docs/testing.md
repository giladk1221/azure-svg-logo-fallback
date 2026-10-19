# Test the logo flow

[Back to README](../README.md) · Deploy first with [Terraform](terraform.md) or [Azure CLI](azure-cli.md).

## 1. Open the demo

Open `https://YOUR-FRONT-DOOR-HOST/logos/demo`, using the deployed `demo_url`. Full mode also serves the example Web App at `/`.

A new catalog contains **ACME.svg** and **CONTOSO.svg**. JEMXX and NEWCO are deliberately absent, so the Function generates their initials. These are fictional test assets. With an existing catalog, use symbols you know are present or absent; the deployment does not add samples to it.

## 2. Check the four important cases

Use your browser or inspect response headers with `curl -i`:

| Path | Expected result with a new sample catalog | `X-Logo-Result` |
|---|---|---|
| `/logos/ACME.svg` | Original SVG, HTTP 200 | `original` |
| `/logos/JEMXX.svg` | Generated **JE**, HTTP 200 | `fallback` |
| `/logos/ACME.svg?explicit=true` | Original SVG, HTTP 200 | `original` |
| `/logos/JEMXX.svg?explicit=true` | HTTP 404 with `Cache-Control: no-store` | `explicit-not-found` |

`explicit=true` means **original only**. Normal missing-logo requests still return a generated SVG with HTTP 200. The Function checks Storage first; the Front Door route does not perform a 404 redirect or failover.

```sh
curl -i 'https://YOUR-FRONT-DOOR-HOST/logos/JEMXX.svg'
curl -i 'https://YOUR-FRONT-DOOR-HOST/logos/JEMXX.svg?explicit=true'
python3 scripts/smoke.py https://YOUR-FRONT-DOOR-HOST
```

For your existing catalog:

```sh
python3 scripts/smoke.py https://YOUR-FRONT-DOOR-HOST --original EXISTING_KEY --missing KNOWN_ABSENT_KEY
```

Supply keys without `.svg`, preserving the stored filename's case. The smoke script also covers the forced-fallback and legacy paths.

## 3. Observe caching and private access

Repeat the same SVG URL. Front Door may return `X-Cache: TCP_HIT`; that response does not call the Function. The smoke script reports caching but does not require a hit. Originals cache for 300 seconds, generated SVGs for 60 seconds. A newly uploaded original replaces a cached placeholder after expiry, or after a targeted Front Door purge. Generated placeholders are not saved to Storage.

Opening the Function/Web App's direct `azurewebsites.net` URL from the public internet should fail. Public Storage access is also disabled. A portal Storage-browser 403 from your laptop can therefore be expected: use an approved private network connection and Blob data permissions. Do not enable public access to make the demo work.

For stricter testing, see the [23-check full-mode acceptance command](validation.md#repeat-the-full-demo-http-acceptance-checks) and [security settings](security.md). HTTP 403 alone does not prove that Private Link and identity permissions are configured correctly.

## Troubleshooting

| Symptom | Check |
|---|---|
| No matching Private Link request yet | Wait for Azure to create it, then rerun the approval command. Verify the origin targets the intended Function resource ID |
| Connection is `Approving` | Allow it to reach `Approved`; the helper handles retries. Keep public origin access disabled |
| Front Door HTML 404, `X-Cache: CONFIG_NOCACHE` | Route/config propagation may still be in progress. Wait and retry; also check hostname and route patterns |
| App 404, `X-Logo-Result: explicit-not-found` | Expected only for a missing original with exact `explicit=true`, or that flag on the forced-fallback route |
| 502, `X-Logo-Result: origin-error` | Check catalog name/container, private DNS/connectivity, managed-identity reader permission and Function logs. A Storage failure is not treated as a missing logo |
| Function fails to start | Confirm the package upload completed, host Storage identity/DNS access works and trigger sync succeeded. Initial container startup can take several minutes |
| Upload VM SKU unavailable | Set `publisher_vm_size` to an available x64 SKU with quota, then retry the same deployment |
| Original just uploaded still shows initials | Wait for the 60-second placeholder TTL or purge that exact Front Door path; ensure the Blob key matches case |

## Local checks before changing the code

```sh
npm test
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/package.py
# Terraform checks, if installed:
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
terraform -chdir=terraform test
```

These checks create no Azure resources. GitHub Actions also runs the validation suite; it does not deploy into a subscription.
