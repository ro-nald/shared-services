# Shared Services

Platform infrastructure shared across product teams. Manages container registries,
Terraform deployment roles, and supporting AWS services.

## What's in this repo

```text
terraform/
├── environments/
│   ├── core/   # Stage 0 — S3 state bucket, GitHub OIDC provider, CI role (manual only)
│   ├── iam/    # Stage 1 — IAM deployer roles and governance controls
│   └── dev/    # Stage 2 — Dev environment services (ECR, GitHub OIDC)
├── modules/
│   └── aws/
│       └── ecr/  # Reusable ECR repository module
└── policies/
    └── iam/      # OPA/Conftest policy gates (enforced in CI)

scripts/
└── bootstrap.py  # Guided one-time setup CLI
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.10
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) ≥ 2.x, configured with admin credentials
- [gh CLI](https://cli.github.com/) ≥ 2.x
- [uv](https://docs.astral.sh/uv/) (runs the bootstrap CLI — installs Python and dependencies automatically)

## Getting started

There is a deliberate three-stage apply order. Use the bootstrap CLI to run all steps in one guided sequence:

```bash
uv run scripts/bootstrap.py run
```

Or check where you are at any point:

```bash
uv run scripts/bootstrap.py status
```

`uv` reads dependencies from the script itself (PEP 723) — no install step needed.
Install uv: [docs.astral.sh/uv](https://docs.astral.sh/uv/)

### Stage 0 — core bootstrap (manual, once)

Creates the S3 state bucket, GitHub OIDC provider, and `ci-pipeline` IAM role that
CI depends on. Never applied by CI.

```bash
uv run scripts/bootstrap.py apply-core
```

See [terraform/environments/core/README.md](terraform/environments/core/README.md)
for full details, including the manual process if you prefer not to use the CLI.

### Stage 1 — IAM deployer roles

After core is applied, migrate the `iam` environment state to S3:

```bash
uv run scripts/bootstrap.py migrate-state iam
```

From this point on, `iam` is applied automatically by CI on every merge to `main`
(with a required reviewer gate for the `iam-production` GitHub Environment).

See [terraform/environments/iam/README.md](terraform/environments/iam/README.md)
for full details, including how to add a team role.

### Stage 2 — dev services

```bash
uv run scripts/bootstrap.py migrate-state dev
```

From this point on, `dev` is applied automatically by CI on every merge to `main`.

See [terraform/environments/dev/README.md](terraform/environments/dev/README.md)
for full details.

### Configure GitHub

Write the `TF_STATE_BUCKET` variable and `CI_PIPELINE_ROLE_ARN` secret to the
repository so CI jobs can authenticate and access state:

```bash
uv run scripts/bootstrap.py configure-github
```

## CI/CD

After bootstrap, pull requests trigger:

- **fmt** — `terraform fmt -check`
- **validate-iam / validate-dev** — syntax validation (no AWS credentials needed)
- **plan-iam** — plan with OPA/Conftest policy gate (path-filtered to `iam/**`)
- **plan-dev** — plan (path-filtered to `dev/**`)

Merges to `main` trigger:

- **apply-iam** — pauses for required reviewer approval (`iam-production` environment)
- **apply-dev** — runs after `apply-iam` succeeds

See [.github/workflows/terraform.yml](.github/workflows/terraform.yml) for the full workflow.

## Adding a team IAM role

Teams request a dedicated Terraform deployer role by opening a pull request.
See [terraform/environments/iam/README.md](terraform/environments/iam/README.md#adding-a-team-role).

## Team onboarding

Development teams consume platform outputs (ECR URLs, deployer role ARNs) via the team bootstrap
CLI in the `platform-tooling` repository — **not** by cloning this repo. Teams never access
Terraform state directly; all values are published to SSM Parameter Store after each CI apply.

Once the platform team has added a team role (see [Adding a team IAM role](#adding-a-team-iam-role)),
they run the team bootstrap CLI to configure the team's GitHub repository:

```bash
uv run team-bootstrap/main.py run \
  --namespace $SSM_NAMESPACE \
  --team-slug team-<slug> \
  --state-bucket $TF_STATE_BUCKET
```

This generates `backend.hcl` for the team's own Terraform state and writes all required
GitHub Actions variables and secrets to their repository.

## Further reading

- [IAM Governance](docs/iam-governance.md) — governance patterns, auditing strategy,
  and the rationale behind key design decisions
