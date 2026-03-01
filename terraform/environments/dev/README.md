# Dev Environment

Manages shared development infrastructure: ECR repositories and the GitHub Actions OIDC
role that allows CI/CD pipelines to push container images.

This is **Stage 2**. The IAM bootstrap environment (`environments/iam/`) must be applied
first.

## What it manages

| Resource | Purpose |
|---|---|
| ECR repositories | Container image storage for dev services |
| ECR lifecycle policies | Image retention (tagged count, untagged expiry) |
| GitHub OIDC IAM role | Allows GitHub Actions workflows to push images without long-lived credentials |

## Prerequisites

- Terraform ≥ 1.5
- Stage 1 applied — deployer role ARN available from `environments/iam/` outputs
- AWS credentials that can assume the deployer role

## Applying (Stage 2)

### Path A — TFVars (recommended)

No credentials enter the shell. Terraform assumes the deployer role internally via the
provider's `assume_role` block.

```bash
cd terraform/environments/dev

# Copy the deployer role ARN from Stage 1
ROLE_ARN=$(cd ../iam && terraform output -raw terraform_deployer_dev_role_arn)

# Add it to your local tfvars (not committed — add terraform.tfvars to .gitignore)
echo "terraform_role_arn = \"${ROLE_ARN}\"" >> terraform.tfvars

terraform init
terraform apply
```

### Path B — Named AWS profile

Useful if you prefer to manage credentials outside of Terraform variables.

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
├── main.tf           # Provider config (with optional assume_role) and ECR module call
├── variables.tf      # Input variables
├── terraform.tfvars  # Variable values (do not commit sensitive values)
└── outputs.tf        # Repository URLs, ARNs, and GitHub Actions role ARN
```

## Variables reference

| Variable | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `eu-west-2` | AWS region |
| `github_org` | string | — | GitHub organisation name |
| `github_allowed_repos` | list(string) | — | Repos allowed to push images via OIDC |
| `repositories` | map(object) | — | ECR repositories to create |
| `tags` | map(string) | `{}` | Common resource tags |
| `terraform_role_arn` | string | `""` | Deployer role ARN from Stage 1 (Path A) |

## Adding a repository

Edit `terraform.tfvars` and add an entry to `repositories`:

```hcl
repositories = {
  "dev/service-a" = {}
  "dev/service-b" = {
    tagged_image_count = 5
  }
  "dev/my-new-service" = {   # <-- add here
    scan_on_push         = true
    image_tag_mutability = "IMMUTABLE"
  }
}
```

## Outputs reference

| Output | Description |
|---|---|
| `repository_urls` | Map of repository name → ECR URL |
| `repository_arns` | Map of repository name → ECR ARN |
| `github_actions_role_arn` | ARN for GitHub Actions workflows to assume |
