# Logo demo without the sample website

Creates the private Function and its dependencies, Front Door Premium and WAF.
No Web App or APIM is created. Open `/logos/demo` on the Front Door hostname.

From the repository root:

```sh
cp terraform/examples/logo-only/terraform.tfvars.example terraform/demo.tfvars
```

Fill in the placeholders and follow the [Terraform guide](../../../docs/terraform.md).
Use a fresh state for a new installation.

[All deployment choices](../../../docs/components.md)
