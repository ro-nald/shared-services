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

Or manually:

```bash
cd terraform/account-bootstrap

terraform init
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

2. **Set the deployer role ARN in CI** as a GitHub Actions variable or secret
   for the environment:

   ```
   TF_VAR_terraform_role_arn = <deployer_role_arn from terraform output>
   ```

3. **For human (local) access**, add a named profile in `~/.aws/config`:

   ```ini
   [profile terraform-dev]
   role_arn          = <deployer_role_arn>
   source_profile    = <your-sso-profile>
   role_session_name = terraform-dev
   ```

## State

This stack uses local state. The generated `terraform.tfstate` file is
gitignored — store it in a private location (encrypted disk or a private S3
bucket). Losing the state does not destroy the role, but re-importing would
be needed to manage it with Terraform again.

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
