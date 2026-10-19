# existing-apim
Copy `terraform.tfvars.example` to `terraform/demo.tfvars`, replace every placeholder, and follow the [deployment guide](../../../docs/deployment.md).

These are inputs to the shared Terraform root, not separate copies of the infrastructure. Run Terraform with `-chdir=terraform` from the repository root. Keep one state and variable file per installation. Never switch `mode` in a deployed state to reuse a different gateway.
