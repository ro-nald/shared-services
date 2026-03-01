# IAM Governance

Architectural reference for how Terraform deployer roles are managed in this repository.
This document explains the _why_ behind the design — for operational how-to, see
[terraform/environments/iam/README.md](../terraform/environments/iam/README.md).

## Core model

Every Terraform environment is applied under a dedicated IAM role scoped to exactly the
permissions that environment needs. No environment shares a role or uses long-lived
admin credentials.

```text
Developer / CI
     │
     │  sts:AssumeRole / sts:AssumeRoleWithWebIdentity (OIDC)
     ▼
terraform-deployer-<env> / ci-pipeline    (scoped permissions + permission boundary)
     │
     │  applies
     ▼
Terraform environment
```

### Three-stage environment structure

```text
terraform/environments/
├── core/   # Stage 0 — manual only, forever
│             Creates: S3 state bucket, GitHub OIDC provider, ci-pipeline role
├── iam/    # Stage 1 — CI-managed after core is applied
│             Creates: terraform-deployer-* roles and permission boundary
└── dev/    # Stage 2 — CI-managed after iam is applied
              Creates: ECR repositories, GitHub Actions ECR push role
```

`core` is the only environment never applied by CI — it creates the CI role itself,
which would be a circular dependency. Changes to `core` are deliberate, manual,
platform-team operations. See [terraform/environments/core/README.md](../terraform/environments/core/README.md)
for the one-time bootstrap sequence.

## Why PR-as-audit-trail (GitOps)

Each team's IAM role definition lives in a file under `terraform/environments/iam/teams/`.
Changes to that file can only reach `main` via a pull request that is:

1. Approved by the team lead (proof that the team owns and understands the change)
2. Approved by the platform team (proof that the platform team has reviewed the permissions)
3. Passing automated OPA/Conftest policy checks in CI

This means the git history of any team file is a complete, tamper-evident record of every
permission change: who proposed it, who approved it, when it merged, and the exact diff.

Alternatives considered:

| Alternative | Why not chosen |
|---|---|
| Platform team owns all role changes | Creates a bottleneck; removes team accountability |
| Self-service portal (Backstage, Port) | Higher complexity, duplicates what a PR already provides |
| Terraform Cloud audit logs | Adds value at scale but not needed at current project size |

## Permission set composition

Teams do not write raw IAM actions. Instead, `permission-sets.tf` (platform-owned) defines
reusable permission-set data sources for each AWS service area:

| Data source | Services covered |
|---|---|
| `pset_ecr_manage` | ECR repositories and images |
| `pset_s3_manage` | S3 buckets and objects |
| `pset_ec2_manage` | EC2 instances, AMIs, security groups |
| `pset_vpc_manage` | VPCs, subnets, route tables, internet gateways |
| `pset_iam_service_roles` | IAM roles and policies for services (not users) |
| `pset_sts_caller_identity` | Read current AWS identity |

Teams compose their role policy using `source_policy_documents`:

```hcl
data "aws_iam_policy_document" "team_payments_permissions" {
  source_policy_documents = [
    data.aws_iam_policy_document.pset_ec2_manage.json,
    data.aws_iam_policy_document.pset_s3_manage.json,
    data.aws_iam_policy_document.pset_vpc_manage.json,
    data.aws_iam_policy_document.pset_sts_caller_identity.json,
  ]
}
```

If a team needs a permission that does not exist in any set, they open a separate PR
to `permission-sets.tf`. That file requires platform team approval only (CODEOWNERS),
making new permission sets a deliberate, reviewed action.

This prevents bespoke role sprawl while keeping the composition visible in code.

## Permission boundaries

Every team deployer role has a `permissions_boundary` set to the `team-deployer-boundary`
policy. This is a hard ceiling enforced by AWS at runtime — the effective permissions of
a role are the _intersection_ of the attached policy and the boundary, regardless of what
policies are attached.

The boundary covers the maximum superset of services any team is permitted to manage.
It explicitly omits:

- IAM user management (`iam:CreateUser`, `iam:DeleteUser`, etc.)
- AWS Organizations actions
- CloudTrail and AWS Config management (audit infrastructure must not be modifiable by teams)
- Billing and cost management

An OPA/Conftest policy gate in CI rejects any team role definition that omits
`permissions_boundary`. This makes the boundary non-negotiable — a team cannot
accidentally or intentionally remove it.

## Audit layers

Two complementary layers provide a complete audit trail.

### Definition audit (git)

Answers: _What permissions were approved, by whom, and when?_

```bash
# Full history of a team's role definition
git log --oneline --follow terraform/environments/iam/teams/team-payments.tf

# Who approved a specific change
git show <commit-hash>   # links back to the PR and its reviewers
```

### Usage audit (AWS CloudTrail)

Answers: _When were these permissions exercised, and by whom?_

CloudTrail records every IAM API call independently of Terraform:

- `CreateRole`, `AttachRolePolicy` — when a role was created and what policies were attached
- `AssumeRole` — which developer or CI job assumed which role, at what timestamp, from which IP

Useful queries:

```bash
# All role creations in the last 7 days (CloudTrail Lake / Athena)
SELECT eventTime, userIdentity.arn, requestParameters.roleName
FROM cloudtrail_logs
WHERE eventName = 'CreateRole'
  AND eventTime > now() - interval '7' day

# All assumptions of a specific role
SELECT eventTime, userIdentity.arn, requestParameters.roleArn
FROM cloudtrail_logs
WHERE eventName = 'AssumeRole'
  AND requestParameters.roleArn LIKE '%terraform-deployer-team-payments%'
```

### Drift detection (AWS Config)

AWS Config continuously evaluates actual IAM state against expected rules. Recommended
rules to enable:

- `iam-role-managed-policy-check` — alerts if the permission boundary policy is detached
- `iam-policy-no-statements-with-admin-access` — alerts if a role gains admin
- Custom rules for required tag presence (`Purpose`, `Team`, `ManagedBy`)

Drift alerts when a role is modified outside Terraform (e.g. via the AWS console).

## Same-repo vs separate IAM repo

The `environments/iam/` directory lives alongside the service environments in the same
`shared-services` repository. This is an intentional choice for the current project stage.

**Why same repo:**

- Atomic PRs: adding a new service and its IAM role lands in one PR with one approval
- No cross-repo ARN-sharing mechanism needed (role ARNs are Terraform outputs in the same tree)
- Single onboarding point for new engineers
- Path-filtered CI jobs provide environment-level separation without repo-level complexity

**When to extract to a separate repo:**

- When dedicated IAM/security administrators exist who are separate from service engineers,
  and repo-level access enforcement is needed
- When compliance frameworks (SOC 2, ISO 27001, PCI-DSS) require demonstrable separation
  of duties at the repository level
- When the IAM environment needs a fundamentally different CI/CD pipeline or approval process

**Design for extractability:**

Environments do not reference each other's Terraform state directly. The deployer role ARN
is a plain variable (`terraform_role_arn`) set by the developer or CI — it can be sourced
from a `terraform output` call, AWS SSM Parameter Store, or a CI secret. This mechanism
works identically in a same-repo and a separate-repo topology, so extraction requires only
moving files and updating CI pipeline paths — no Terraform code changes.

## Role naming and tagging conventions

| Attribute | Convention | Example |
|---|---|---|
| Role name | `terraform-deployer-<team>` | `terraform-deployer-team-payments` |
| Policy name | `terraform-deployer-<team>-policy` | `terraform-deployer-team-payments-policy` |
| Tag: `Purpose` | `terraform-deployer` | (used by role-picker CLI for discovery) |
| Tag: `Team` | team slug | `payments` |
| Tag: `Environment` | environment name | `dev` |
| Tag: `ManagedBy` | `terraform` | (all resources) |

The `Purpose=terraform-deployer` tag is the primary filter used by the role-picker CLI:

```bash
aws resourcegroupstaggingapi get-resources \
  --resource-type-filters iam:role \
  --tag-filters Key=Purpose,Values=terraform-deployer
```
