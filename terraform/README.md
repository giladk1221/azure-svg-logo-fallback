# Terraform deployment

Start with [prerequisites](../docs/deployment.md), then follow the [five-step Terraform guide](../docs/terraform.md).

| Example | Creates |
|---|---|
| [Full demo](examples/full-demo/) | Front Door Premium, WAF, private Function/Storage and Web App |
| [Existing Front Door](examples/existing-front-door/) | Function/dependencies and logo routing on an existing Premium endpoint |
| [Function only](examples/function-only/) | Function/dependencies; connect it using your own Front Door configuration |

Run Terraform from this shared root, **not** an example directory. The example folders contain variable files, not standalone modules. Use a separate checkout/state per installation. State and plans can contain sensitive values; keep them private.

[Inputs](variables.tf) · [Outputs](outputs.tf) · [Integration and reuse](../docs/existing-front-door.md) · [Repository overview](../README.md)
