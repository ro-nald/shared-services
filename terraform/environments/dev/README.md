# Dev Environment

Manages dev-environment-specific AWS infrastructure.

Requires `platform/iam/` and `platform/registry/` to be applied first.

## What it manages

Dev-specific resources go here. The shared container registry lives in `platform/registry/`
and is consumed by all environments — add repositories there, not here.

## Prerequisites

- Terraform ≥ 1.10
- `platform/iam/` applied — deployer role ARN available from its outputs
- AWS credentials that can assume the deployer role

## Applying

### Path A — TFVars (recommended)

No credentials enter the shell. Terraform assumes the deployer role internally via the
provider's `assume_role` block.

```bash
cd terraform/environments/dev

# Copy the deployer role ARN from account-bootstrap (requires local state from bootstrap-account)
ROLE_ARN=$(cd ../../account-bootstrap && terraform output -raw deployer_role_arn)

# Add it to your local tfvars
echo "terraform_role_arn = \"${ROLE_ARN}\"" >> terraform.tfvars

terraform init
terraform apply
```

### Path B — Named AWS profile

```bash
# Add to ~/.aws/config:
# [profile terraform-dev]
# role_arn          = <arn-from-stage-1>
# source_profile    = default
# role_session_name = terraform-dev

export AWS_PROFILE=terraform-dev
terraform apply
```

When using Path B, leave `terraform_role_arn` unset (or set it to `""`) in `terraform.tfvars`.

## File structure

```text
environments/dev/
├── main.tf           # Provider config with optional assume_role
├── variables.tf      # Input variables
├── dev.auto.tfvars   # Committed project variable values
└── terraform.tfvars  # Local overrides (gitignored, optional)
```

## Variables reference

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `aws_region` | string | `ap-east-1` | AWS region |
| `tags` | map(string) | `{}` | Common resource tags |
| `terraform_role_arn` | string | `""` | Deployer role ARN from `account-bootstrap` (Path A) |
