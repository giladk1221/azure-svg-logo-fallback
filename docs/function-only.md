# Quick start: deploy only the Function App

[Back to README](../README.md) · [All component choices](components.md)

**Choose `function_only`. No APIM, Front Door, WAF or sample Web App is deployed.**
The application is JavaScript on Node.js 22; Python only runs the deployment tools.

| Your starting point | Use this path |
|---|---|
| Need a new Function App | [Create the Function and its dependencies](#create-the-function-and-its-dependencies) below |
| Already have a compatible Function App and Storage/identity/networking | [Publish code only](#publish-code-only-to-an-existing-function-app) |
| Need a public demo URL, but no sample website | Choose `logo_only`: [Function + Front Door](components.md#function--front-door-without-the-website) |

## Create the Function and its dependencies

Use Azure CLI + Python 3.10+ for the shortest path; Terraform is optional.
You need permission to create Azure resources and assign roles. Commands use Bash/zsh.

### 1. Get the repo and sign in

```sh
git clone https://github.com/giladk1221/azure-svg-logo-fallback.git
cd azure-svg-logo-fallback
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
```

If already cloned, start from the repository root. See [setup](deployment.md) for
region/quota and resource-provider requirements.

### 2. Prepare one configuration file

```sh
mkdir -p .deploy
# Skip key generation if you already have this key; do not overwrite it.
ssh-keygen -t ed25519 -f .deploy/publisher-key -N ''
cat .deploy/publisher-key.pub
cp azure-cli/examples/function-only.json my-demo.json
```

Edit just these values in `my-demo.json`:

| Value | What to put there |
|---|---|
| `subscription_id` | The subscription selected above |
| `name` | A globally unique name, 3–18 lowercase letters/digits, starting with a letter |
| `location` | Your region; the example uses `westeurope` |
| `publisher_ssh_public_key` | The complete `.pub` line printed above |

Keep `"mode": "function_only"` and `"publish_artifacts": true`.
The temporary uploader transfers the package into private Storage; it does not
serve application traffic. No SSH connection is needed.

### 3. Preview, then deploy

```sh
python3 azure-cli/deploy.py render --config my-demo.json
# Inspect .deploy/<name>/workload.json, then deploy:
python3 azure-cli/deploy.py deploy --config my-demo.json
```

`render` works offline and creates no Azure resources. For an Azure what-if before
creation, use [the optional plan step](azure-cli.md#2-render-and-review).
The deployment creates this working unit:

| Component | Why it stays with the Function |
|---|---|
| Function App + Linux App Service plan | Runs the Node.js code; an existing compatible plan can be reused |
| Host Storage and package container | Runtime storage and the deployed ZIP |
| Logo Storage and container | Original SVGs; an existing catalog can be reused |
| Managed identity + role assignments | Reads Storage without account keys |
| VNet, Blob private endpoints and DNS | Lets the Function read private Storage; compatible networking can be reused |
| Application Insights + Log Analytics | Logs and diagnostics in this demo |
| Temporary uploader VM and outbound resources | Uploads code/sample logos; remove after successful publishing |

[Reuse an existing plan, network or logo catalog](existing-front-door.md#reuse-existing-dependencies)
to avoid creating duplicates. Host Storage, identity and monitoring are still created
by this path. A bare Function resource without its runtime and Storage configuration
would not run this demo.

### 4. Get the result and connect it when ready

The command prints the Function resource ID; keep `.deploy/<name>/manifest.json`.

```sh
az functionapp show --ids YOUR_FUNCTION_RESOURCE_ID --query '{id:id,hostname:defaultHostName,state:state}' -o json
az functionapp function list --resource-group YOUR_WORKLOAD_RG --name YOUR_FUNCTION_NAME --query '[].name' -o tsv
```

Expect `LogoRouter` after publishing and trigger synchronization. This checks
registration, not the complete HTTP/Storage flow.

**The Function is private. A browser on the public internet cannot call its
`azurewebsites.net` hostname yet.** Its VNet integration is outbound access to
Storage, not an inbound endpoint. Choose one connection when you need HTTP access:

- [Add Front Door separately](components.md#add-front-door-to-an-existing-function),
  using this Function's ID and hostname. It does not redeploy the Function.
- Let the customer's infrastructure owner [connect their existing Front Door](existing-front-door.md#function-only).
- For internal access without Front Door, use a separately configured inbound
  Function private endpoint (`sites`), App Service private DNS and a connected
  client. This Function-only template does not create that inbound endpoint.

After connecting, open `/logos/demo` on the reachable endpoint and run:

```sh
python3 scripts/smoke.py https://YOUR-REACHABLE-HOST
```

The sample assumes the new catalog contains ACME and CONTOSO. With a reused catalog,
follow [the testing guide](testing.md) to select an existing logo key.

### 5. Remove the temporary uploader

After package publishing succeeds, the uploader can be removed even if Front Door
will be added later:

```sh
python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json
# Review the listed temporary resources, then:
python3 azure-cli/deploy.py cleanup-publisher --config my-demo.json --yes
```

Set `"publish_artifacts": false` in the same JSON afterwards. The Function,
Storage and its other permanent dependencies remain running and billable.
If you already have a private runner, [skip the temporary uploader](deployment.md#private-runner-alternative).

### Prefer Terraform?

Use the same dependency boundary and a fresh state for this installation:

```sh
cp terraform/examples/function-only/terraform.tfvars.example terraform/demo.tfvars
# Fill subscription_id, name_prefix, location and publisher_ssh_public_key.
python3 scripts/package.py
terraform -chdir=terraform init
terraform -chdir=terraform plan -var-file=demo.tfvars -out=demo.tfplan
terraform -chdir=terraform apply demo.tfplan
terraform -chdir=terraform output -raw function_id
terraform -chdir=terraform output -raw function_hostname
```

Use [Terraform uploader cleanup](terraform.md#5-remove-the-temporary-uploader)
and [teardown](terraform.md#delete-this-installation) for this path. Do not run the
CLI deployment against the same installation.

## Publish code only to an existing Function App

This creates **no infrastructure**. Use a dedicated compatible app: publishing a
ZIP replaces the app's deployed package, including any other functions in that package.

The existing environment must already provide:

- Linux, Node.js 22 and Azure Functions runtime 4, with a hosting/deployment method
  compatible with the selected publishing path.
- Working host Storage and its authentication configuration.
- A managed identity with `Storage Blob Data Reader` on the logo container;
  `AZURE_CLIENT_ID` when choosing a user-assigned identity.
- `LOGO_STORAGE_ACCOUNT` and `LOGO_CONTAINER` app settings and working outbound
  networking/DNS to that private catalog. Do not use a Storage URL as the account name.

Build the ready-to-run package (no npm install or Python runtime is required in the app):

```sh
python3 scripts/package.py
```

**For an existing app already using ZIP deployment** on a compatible Dedicated or
Elastic Premium plan, publish from a machine/runner that can reach its deployment
endpoint:

```sh
az functionapp deployment source config-zip \
  --resource-group YOUR_FUNCTION_RG \
  --name YOUR_FUNCTION_NAME \
  --src .build/function.zip
```

**For an app created by this repo**, keep its external package URL deployment model.
Use [private-runner publishing](deployment.md#private-runner-alternative) or the
[CLI update flow](azure-cli.md#update-the-function-later). Do not mix ZIP deployment
with its Terraform/ARM-managed `WEBSITE_RUN_FROM_PACKAGE` URL. Update the package URL
to the newly hashed ZIP in the owning configuration, then restart and sync triggers.

Flex Consumption uses a different package deployment model; these infrastructure
templates and the external-URL procedure target a Dedicated Linux plan. Review
[Microsoft's deployment methods and private endpoint requirements](https://learn.microsoft.com/en-us/azure/azure-functions/functions-deployment-technologies)
when adapting an existing customer app. Keep its existing access restrictions.
