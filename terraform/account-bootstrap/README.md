# Account Bootstrap

One-time setup for a new workload account (dev, staging, prod, …). Creates
`terraform-deployer-<env>` in the target account so that `ci-pipeline` in the
shared-services account can assume it to deploy environment resources.

Requires `platform/core/` and `platform/iam/` to be applied first.

## What it creates

| Resource | Name | Purpose |
| --- | --- | --- |
| IAM role | `terraform-deployer-<env>` | Assumed by `ci-pipeline` to deploy the environment |
| IAM policy | `terraform-deployer-boundary-<env>` | Permission boundary: hard ceiling on the deployer role |
| Policy attachment | `AdministratorAccess` (AWS managed) | Broad permissions, bounded by the boundary above |

The boundary explicitly denies IAM user management, CloudTrail/Config
modification, billing actions, and Organizations API calls, regardless of what
other policies are attached.

## Prerequisites

- `platform/core/` applied — `ci-pipeline` role exists in the shared-services account
- Admin credentials in the management account (to assume `OrganizationAccountAccessRole`)
- The target workload account already exists (created via Control Tower Account Factory
  or `aws organizations create-account`)

## Applying

Use the bootstrap CLI (recommended):

```bash
uv run scripts/bootstrap.py bootstrap-account \
  --account-id <workload-account-id> \
  --env dev
```

Or manually (generate `backend.hcl` first — see [State](#state) below):

```bash
cd terraform/account-bootstrap

terraform init -backend-config=backend.hcl
terraform apply \
  -var="target_account_id=<workload-account-id>" \
  -var="environment=dev" \
  -var="shared_services_account_id=<shared-services-account-id>"
```

## After applying

1. **Add the account ID to `platform/core/`** so `ci-pipeline` can assume the
   new role:

   ```hcl
   # terraform/platform/core/terraform.tfvars
   workload_account_ids = ["<workload-account-id>"]
   ```

   Then re-apply `platform/core/` (or let CI apply it after merging).

2. **Set the deployer role ARN as a GitHub Actions secret** so CI can assume
   it (replace `DEV` with the environment name in uppercase):

   ```bash
   gh secret set TERRAFORM_DEPLOYER_DEV_ARN \
     --body "$(terraform output -raw deployer_role_arn)"
   ```

   CI maps this secret to `TF_VAR_terraform_role_arn` in the workflow.

3. **For human (local) access**, add a named profile in `~/.aws/config`:

   ```ini
   [profile terraform-dev]
   role_arn          = <deployer_role_arn>
   source_profile    = <your-sso-profile>
   role_session_name = terraform-dev
   ```

## State

State is stored in the shared-services S3 bucket under
`account-bootstrap-<env>/terraform.tfstate` — one key per environment. The
bootstrap CLI writes `backend.hcl` automatically before each run.

To generate it manually:

```bash
BUCKET=$(cd ../platform/core && terraform output -raw state_bucket_name)
cat > backend.hcl <<EOF
bucket       = "$BUCKET"
key          = "account-bootstrap-dev/terraform.tfstate"
region       = "ap-east-1"
use_lockfile = true
encrypt      = true
EOF
```

Change the `key` for each environment (staging, prod, etc.).

## Adding human access (IAM Identity Center)

To allow engineers to assume the deployer role locally via SSO, pass their
IAM Identity Center role ARNs as `additional_trusted_arns`:

```hcl
additional_trusted_arns = [
  "arn:aws:iam::<workload-account-id>:role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_PlatformEngineer_*"
]
```

Or configure IAM Identity Center permission sets in the management account to
grant `sts:AssumeRole` on the deployer role to the appropriate user groups.

## Variables reference

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `target_account_id` | string | required | AWS account ID of the workload account |
| `environment` | string | required | Environment name (dev, staging, prod) |
| `shared_services_account_id` | string | required | Account ID where `ci-pipeline` lives |
| `additional_trusted_arns` | list(string) | `[]` | Extra ARNs that can assume the deployer role |
| `aws_region` | string | `ap-east-1` | AWS region |
| `tags` | map(string) | `{ManagedBy="terraform"}` | Common resource tags |
