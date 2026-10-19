# Full demo

Creates a new Front Door Premium with WAF, private Function and Storage, networking/identity/monitoring, and a separate private Web App.

From the repository root:

```sh
cp terraform/examples/full-demo/terraform.tfvars.example terraform/demo.tfvars
```

Replace the placeholders, then follow the [Terraform guide](../../../docs/terraform.md). Run Terraform against the shared `terraform/` root, not this example directory; use one state per installation.

[Integration and reuse](../../../docs/existing-front-door.md) · [Repository overview](../../../README.md)
