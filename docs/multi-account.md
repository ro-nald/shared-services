# Multi-Account Architecture

How this repository fits into a multi-account AWS organisation, and how to
add new workload accounts.

## Account structure

```text
Management / Control Tower root
├── Security OU
│   ├── log-archive        # Centralised CloudTrail + Config logs (Control Tower)
│   └── audit              # Security Hub, GuardDuty aggregation (Control Tower)
├── Platform OU
│   └── shared-services    # This repo — ECR, state bucket, OIDC provider, deployer IAM roles
└── Workloads OU
    ├── dev                # Dev environment — bootstrapped via account-bootstrap
    ├── staging            # Staging environment
    └── prod               # Production environment
```

The **management account** is used only for AWS Organizations administration,
Control Tower, and billing. No workloads or platform infrastructure run there.

The **shared-services account** is where this repository provisions infrastructure
that all workload accounts consume: the shared ECR registry, the CI pipeline role,
and the governance controls for deployer roles.

Each **workload account** gets a single `terraform-deployer-<env>` role
(created by `terraform/account-bootstrap/`) that `ci-pipeline` assumes
cross-account to deploy resources into it.

## Trust chain

```text
GitHub Actions (OIDC)
     │  sts:AssumeRoleWithWebIdentity
     ▼
ci-pipeline  (shared-services account)
     │  sts:AssumeRole  (cross-account)
     ▼
terraform-deployer-<env>  (workload account)
     │  applies
     ▼
Environment resources  (workload account)
```

The `ci-pipeline` role is scoped to only assume `terraform-deployer-*` roles in
explicitly enrolled account IDs (`var.workload_account_ids` in `platform/core/`).

## Adding a new workload account

### 1. Create the account

Via Control Tower Account Factory (recommended) or:

```bash
aws organizations create-account \
  --email <env>@yourdomain.com \
  --account-name <env>
```

Note the new account ID from the output or:

```bash
aws organizations list-accounts --query "Accounts[?Name=='<env>'].Id" --output text
```

### 2. Bootstrap the account

```bash
uv run scripts/bootstrap.py bootstrap-account \
  --account-id <account-id> \
  --env <env>
```

This assumes `OrganizationAccountAccessRole` in the new account and creates
`terraform-deployer-<env>` with trust back to `ci-pipeline` in shared-services.
The deployer role has `AdministratorAccess` bounded by a permission boundary
that prevents IAM user management, CloudTrail/Config modification, and billing.

### 3. Enrol the account in ci-pipeline

Add the account ID to `platform/core/terraform.tfvars` (this file is gitignored
— edit it locally, do not open a PR for it):

```hcl
workload_account_ids = ["<account-id>"]
```

Then re-apply `platform/core/` using the `platform-bootstrap` role so that
`ci-pipeline` gains `sts:AssumeRole` permission for the new account:

```bash
AWS_PROFILE=platform-bootstrap uv run scripts/bootstrap.py apply-core
```

See [Re-running apply-core](../README.md#re-running-apply-core) for how to
configure the `platform-bootstrap` AWS profile.

### 4. Wire up the CI workflow

Add a new apply job in `.github/workflows/terraform.yml` for the new
environment, setting:

```yaml
env:
  TF_VAR_terraform_role_arn: ${{ secrets.TERRAFORM_DEPLOYER_<ENV>_ARN }}
```

Add the deployer role ARN as a GitHub Actions secret:

```bash
gh secret set TERRAFORM_DEPLOYER_<ENV>_ARN \
  --body "<deployer_role_arn from step 2>"
```

### 5. Create the environment stack

Add `terraform/environments/<env>/` following the pattern in
`terraform/environments/dev/`. The provider's `assume_role` block will
use the cross-account deployer role ARN from `TF_VAR_terraform_role_arn`.

## Human access (IAM Identity Center)

For local Terraform runs, engineers assume the workload account deployer role
via IAM Identity Center (SSO). Configure a permission set that grants
`sts:AssumeRole` on `arn:aws:iam::<account-id>:role/terraform-deployer-<env>`,
then assign it to the appropriate group.

Alternatively, pass IAM Identity Center role ARNs as `additional_trusted_arns`
when running `bootstrap-account` — the deployer role will then directly trust
those principals.

Once a permission set is assigned, engineers add a named profile in
`~/.aws/config`:

```ini
[profile terraform-dev]
role_arn          = arn:aws:iam::<dev-account-id>:role/terraform-deployer-dev
source_profile    = <your-sso-profile>
role_session_name = terraform-dev
```

Then run Terraform with `AWS_PROFILE=terraform-dev` or set
`terraform_role_arn` in a local `terraform.tfvars`.

## Service Control Policies (SCPs)

Apply SCPs at the Workloads OU level to enforce baseline guardrails across all
workload accounts regardless of IAM policies:

| SCP | Purpose |
| --- | --- |
| Deny IAM user creation | Enforce SSO-only human access |
| Deny CloudTrail deletion | Protect the audit trail |
| Deny leaving the organisation | Prevent account hijacking |
| Restrict to approved regions | Cost and compliance control |

SCPs are applied via the management account (Control Tower or Organizations
console) and are outside the scope of this repository.

## State bucket cross-account access

The Terraform state bucket lives in the shared-services account. When CI runs
a workload environment apply, it first assumes `ci-pipeline` (which has S3
read/write on the bucket), then assumes the cross-account deployer role. The S3
operations use the `ci-pipeline` identity — no additional bucket policy is
needed for CI.

For humans running Terraform locally against a workload account, the deployer
role in that account needs read/write access to the team's own state prefix in
the shared-services bucket. This is granted by the `pset_s3_team_state`
permission set (see `platform/iam/permission-sets.tf`) and should be added to
the deployer role policy after the initial bootstrap.
