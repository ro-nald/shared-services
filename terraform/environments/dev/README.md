# Dev Environment

Manages dev-environment-specific AWS infrastructure.

This is **Stage 3**. `platform/iam/` (Stage 1) and `platform/registry/` (Stage 2) must
be applied first.

## What it manages

Dev-specific resources go here. The shared container registry lives in `platform/registry/`
and is consumed by all environments — add repositories there, not here.

## Prerequisites

- Terraform ≥ 1.10
- Stage 1 applied — deployer role ARN available from `platform/iam/` outputs
- AWS credentials that can assume the deployer role

## Applying (Stage 3)

### Path A — TFVars (recommended)

No credentials enter the shell. Terraform assumes the deployer role internally via the
provider's `assume_role` block.

```bash
cd terraform/environments/dev

# Copy the deployer role ARN from Stage 1
ROLE_ARN=$(cd ../../platform/iam && terraform output -raw terraform_deployer_dev_role_arn)

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
└── terraform.tfvars  # Variable values
```

## Variables reference

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `ap-east-1` | AWS region |
| `tags` | map(string) | `{}` | Common resource tags |
| `terraform_role_arn` | string | `""` | Deployer role ARN from Stage 1 (Path A) |
