# Azure CLI deployment

Start with [prerequisites](../docs/deployment.md), then follow the [five-step Azure CLI guide](../docs/azure-cli.md). No Terraform, Bicep or Python Azure SDK is required.

| Example JSON | Creates |
|---|---|
| [full.json](examples/full.json) | Front Door Premium, WAF, private Function/Storage and Web App |
| [logo-only.json](examples/logo-only.json) | Function/dependencies + Front Door Premium/WAF; no Web App |
| [existing-front-door.json](examples/existing-front-door.json) | Function/dependencies and logo routing on an existing Premium endpoint |
| [function-only.json](examples/function-only.json) | Function/dependencies; connect it using your own Front Door configuration |

Run commands from the **repository root**. `deploy.py` handles rendering, workload what-if, deployment, Private Link approval and temporary-uploader cleanup. `template.py` generates the ARM JSON. Keep `.deploy/<name>/manifest.json` for retries and resource ownership; incremental deployments do not automatically delete omitted resources.

[Integration and reuse](../docs/existing-front-door.md) · [Repository overview](../README.md)

[Function-only quick start](../docs/function-only.md) · [Separate optional components](../docs/components.md)
