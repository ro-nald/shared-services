# Core

Bootstrap infrastructure required by all other stacks. Must be applied before
`platform/iam/` or any environment. It is the **only stack that is never managed
by CI** — it creates the CI role itself.

## What it manages

| Resource | Purpose |
| --- | --- |
| S3 bucket | Terraform state for all environments (native S3 locking, no DynamoDB) |
| GitHub OIDC provider | Keyless authentication for GitHub Actions |
| `ci-pipeline` IAM role | Assumed by CI to apply `platform/iam/` and all environments |

## Why this environment exists

CI cannot create the infrastructure it needs to run — there is a bootstrap
problem: GitHub Actions requires an IAM role to assume, that role requires an
OIDC identity provider, and both require Terraform state to be stored somewhere.
None of that can be provisioned by CI itself.

`core` breaks the cycle by providing exactly three things, applied once by a
human with admin credentials:

1. **S3 state bucket** — remote state storage shared by all environments; CI
   needs this to read and write state on every run.
2. **GitHub OIDC provider** — lets GitHub Actions authenticate to AWS without
   storing long-lived credentials as GitHub Secrets (keyless auth).
3. **`ci-pipeline` IAM role** — the identity CI assumes via OIDC; its ARN is
   stored as `CI_PIPELINE_ROLE_ARN` in GitHub Secrets and used by every apply
   workflow.

Once `core` is applied, all subsequent stacks (`platform/iam/`, `environments/dev/`, …)
are managed entirely by CI. `core` itself is never touched by CI — doing so would
create a circular dependency where CI could accidentally destroy the role it is
running as.

## Prerequisites

- Terraform ≥ 1.10
- AWS CLI with admin-level credentials (`AdministratorAccess` or equivalent)
- `gh` CLI ≥ 2.x (for `configure-github` step)
- `uv` (runs the bootstrap CLI — installs Python and dependencies automatically)
- A local `terraform.tfvars` (gitignored — copy from the example and set `github_org`):

  ```bash
  cp terraform/platform/core/terraform.tfvars.example terraform/platform/core/terraform.tfvars
  ```

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
cd terraform/platform/core

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
platform/core/
├── main.tf                    # Provider config + empty backend "s3" {}
├── state.tf                   # S3 bucket
├── oidc.tf                    # GitHub OIDC provider
├── ci.tf                      # ci-pipeline IAM role
├── variables.tf
├── terraform.tfvars           # gitignored — copy from terraform.tfvars.example
├── terraform.tfvars.example   # committed template for local configuration
└── outputs.tf
```

## Outputs reference

| Output | Description |
| --- | --- |
| `ssm_namespace_id` | 6-character hex namespace ID used to scope all shared-services SSM parameters |
| `state_bucket_name` | S3 bucket name — needed for `backend.hcl` in all environments |
| `ci_pipeline_role_arn` | ARN for the `CI_PIPELINE_ROLE_ARN` GitHub Secret |
| `next_steps` | Guidance on completing the bootstrap |

## Making changes to core

`core` is a deliberate, infrequent operation. There is no CI apply job for this
environment. Changes require:

1. Admin AWS credentials
2. A pull request approved by the platform team
3. Manual `terraform apply` after merge

If you bump a provider version, regenerate the lock file for all target platforms
before committing (see [Updating providers](../../README.md#updating-providers)).
