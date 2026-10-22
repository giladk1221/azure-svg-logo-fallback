# Function only

Creates the private Function and its dependencies. It creates no Front Door or Web App; you must connect the Function to a Premium private origin before testing from the internet. See the [Function-only quick start](../../../docs/function-only.md) for dependencies, publishing and connection options.

From the repository root:

```sh
cp terraform/examples/function-only/terraform.tfvars.example terraform/demo.tfvars
```

Replace the placeholders, then follow the [Terraform guide](../../../docs/terraform.md). Run Terraform against the shared `terraform/` root, not this example directory; use one state per installation.

[Integration and reuse](../../../docs/existing-front-door.md) · [Repository overview](../../../README.md)
