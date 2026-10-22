# Optional website, deployed separately

Deploys the private sample Web App and a Linux B1 plan (or reuses a supplied plan).
It creates no Function, Storage or Front Door. Its `/logos/demo` link works after
Front Door routes `/logos/*` to the Function and `/*` to this website.

Follow the copy/edit/plan/apply steps in [component deployment](../../../docs/components.md#optional-demo-website).
Run Terraform in this directory, using its own state. This is different from the
`terraform/examples/` variable presets, which use the shared root.
