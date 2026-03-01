# Core Environment

Bootstrap infrastructure required by all other environments. This is **Stage 0**
and must be applied before `iam/` or `dev/`. It is the **only environment that is
never managed by CI** — it creates the CI role itself.

## What it manages

| Resource | Purpose |
| --- | --- |
| S3 bucket | Terraform state for all environments (native S3 locking, no DynamoDB) |
| GitHub OIDC provider | Keyless authentication for GitHub Actions |
| `ci-pipeline` IAM role | Assumed by CI to apply `iam/` and `dev/` |

## Prerequisites

- Terraform ≥ 1.10
- AWS CLI with admin-level credentials (`AdministratorAccess` or equivalent)
- `gh` CLI ≥ 2.x (for `configure-github` step)
- `uv` (runs the bootstrap CLI — installs Python and dependencies automatically)

## Applying (guided)

The bootstrap CLI handles the full sequence, including state migration:

```bash
uv run scripts/bootstrap.py run
```

Or step by step:

```bash
uv run scripts/bootstrap.py check           # verify prerequisites
uv run scripts/bootstrap.py apply-core      # apply + migrate core state to S3
uv run scripts/bootstrap.py migrate-state iam
uv run scripts/bootstrap.py migrate-state dev
uv run scripts/bootstrap.py configure-github
```

## Applying (manual)

If you prefer not to use the CLI:

```bash
cd terraform/environments/core

# First run: local backend
terraform init
terraform apply

# Note the bucket name:
BUCKET=$(terraform output -raw state_bucket_name)

# Generate backend.hcl
cat > backend.hcl <<EOF
bucket       = "$BUCKET"
key          = "core/terraform.tfstate"
region       = "ap-east-1"
use_lockfile = true
encrypt      = true
EOF

# Migrate core state to S3
terraform init -migrate-state -backend-config=backend.hcl
```

Repeat for `iam/` and `dev/` using `key = "iam/terraform.tfstate"` and
`key = "dev/terraform.tfstate"` respectively.

## If the OIDC provider already exists

If GitHub Actions was previously configured manually, the OIDC provider exists
but is unmanaged. Import it before applying:

```bash
OIDC_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn,'token.actions.githubusercontent.com')].Arn" \
  --output text)

terraform import aws_iam_openid_connect_provider.github "$OIDC_ARN"
```

## File structure

```text
environments/core/
├── main.tf          # Provider config + empty backend "s3" {}
├── state.tf         # S3 bucket
├── oidc.tf          # GitHub OIDC provider
├── ci.tf            # ci-pipeline IAM role
├── variables.tf
├── terraform.tfvars
└── outputs.tf
```

## Outputs reference

| Output | Description |
| --- | --- |
| `state_bucket_name` | S3 bucket name — needed for `backend.hcl` in all environments |
| `ci_pipeline_role_arn` | ARN for the `CI_PIPELINE_ROLE_ARN` GitHub Secret |
| `next_steps` | Guidance on completing the bootstrap |

## Making changes to core

`core` is a deliberate, infrequent operation. There is no CI apply job for this
environment. Changes require:

1. Admin AWS credentials
2. A pull request approved by the platform team
3. Manual `terraform apply` after merge
