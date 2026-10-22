# Deploy only the Function App

Use the existing `function_only` mode. It deploys the Function and its dependencies,
with **no APIM, Front Door, WAF or sample Web App**. The full demo remains available
through `full`; no code changes are needed to choose either option.

## Quick start with Azure CLI

First complete [setup](deployment.md): clone the repo, sign in to Azure, select your
subscription and prepare the uploader's SSH public key. You need Azure CLI and
Python 3.10+; Terraform is not required. Run these commands from the repository root.

1. Copy the existing Function-only configuration:

   ```sh
   cp azure-cli/examples/function-only.json my-demo.json
   ```

2. Edit `my-demo.json`: set `subscription_id`, a globally unique `name` (3–18 lowercase
   letters/digits, starting with a letter), `location` and `publisher_ssh_public_key`.
   Keep `"mode": "function_only"` and `"publish_artifacts": true`.

3. Preview and deploy:

   ```sh
   python3 azure-cli/deploy.py render --config my-demo.json
   # Review .deploy/<name>/workload.json, then:
   python3 azure-cli/deploy.py deploy --config my-demo.json
   ```

4. Keep `.deploy/<name>/manifest.json`, which contains the Function resource ID.
   **The Function is private**, so its hostname is not directly accessible from the
   internet. Follow [existing Front Door integration](existing-front-door.md#function-only)
   when ready to connect and test it. This does not require deploying the sample website.

5. After successful publishing, remove the temporary uploader:

   ```sh
   python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json
   # Review the listed temporary resources, then:
   python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json --yes
   ```

   Set `"publish_artifacts": false` afterwards to prevent recreating the uploader.
   The Function and its permanent dependencies remain running and billable.

## What stays with the Function?

The deployment includes its hosting plan, host/package Storage, logo Storage,
managed identity and permissions, private networking/DNS, and monitoring. A
compatible existing plan, network or logo catalog can be [reused](existing-front-door.md#reuse-existing-dependencies).
The temporary uploader is only for publishing; it is not part of the request flow.

Use `existing_front_door` if you want the deployment to create a new Function and
connect it to an existing Premium endpoint automatically. Use `full` for the complete
demo. Keep the mode of an existing installation unchanged; these choices are for new
installations, not for removing parts of a running demo.

Prefer Terraform? Copy
[`terraform/examples/function-only/terraform.tfvars.example`](../terraform/examples/function-only/terraform.tfvars.example)
and follow the [Terraform guide](terraform.md), including uploader cleanup.

[Back to README](../README.md)
