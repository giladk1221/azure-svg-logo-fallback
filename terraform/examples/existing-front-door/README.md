# Existing Front Door

Adds a private Function and its dependencies, plus logo routing on an existing Front Door Premium endpoint. Review path conflicts and shared-resource ownership before deployment.

From the repository root:

```sh
cp terraform/examples/existing-front-door/terraform.tfvars.example terraform/demo.tfvars
```

Replace the placeholders, then follow the [Terraform guide](../../../docs/terraform.md). Run Terraform against the shared `terraform/` root, not this example directory; use one state per installation.

[Integration and reuse](../../../docs/existing-front-door.md) · [Repository overview](../../../README.md)
