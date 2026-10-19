# Validation scope

The repository includes local Function tests, deterministic packaging, Terraform formatting/provider validation, mocked infrastructure plans and a post-deployment HTTP smoke script. GitHub Actions runs the local checks without Azure credentials.

Mocked plans do not create Azure resources. They verify configuration branches and security invariants, not Azure regional capacity, tenant policies, private DNS routing, APIM token issuance, package startup or Front Door propagation. The APIM/Terraform architecture in this repository must pass a real deployment acceptance run in the customer's chosen subscription before being considered validated end to end.

## Azure acceptance checklist

1. Full demo: apply, approve the exact Front Door Private Link request, run smoke checks, disable APIM public access, rerun checks, and confirm direct public APIM/Function/Storage access is blocked.
2. Existing APIM: verify private DNS and routing from the gateway, check the new paths do not collide, and ensure inherited policies do not change the query/cache behavior. Run the smoke script with actual catalog keys.
3. Function only: call from a connected private runner using an authorized identity. Confirm a different identity and an unauthenticated request cannot access the Function.
4. Observe stored originals, normal generated SVGs, original+explicit=200, missing+explicit=404/no-store and no mixing across the Front Door cache key.
5. Add a new original for a previously missing symbol and verify it replaces the generated image after TTL expiry or a scoped purge.
6. Confirm catalog access errors produce 502/no-store, not a placeholder. Use a separate sandbox for failure injection.
7. Verify structured Function events in App Insights and remove the optional publisher with a second apply.

Do not run destructive or outage-injection tests against an existing shared gateway or customer catalog.
