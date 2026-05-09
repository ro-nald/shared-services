# Shared Services

This repo provisions and manages the AWS platform infrastructure shared across all product
teams. It owns three things:

- **Container registry** — a single shared ECR registry with lifecycle policies and
  keyless GitHub Actions push access, consumed by all environments
- **IAM deployer roles** — scoped Terraform roles for each environment and team, governed
  by a permission boundary and an OPA policy gate in CI
- **Bootstrap infrastructure** — the S3 state bucket, GitHub OIDC provider, and CI role
  that everything else depends on

**Platform team:** use this repo to add team roles, provision new environments, and manage
shared platform resources. See [Adding a team IAM role](#adding-a-team-iam-role) and
[Getting started](#getting-started).

**Product teams:** consume outputs (ECR URLs, deployer role ARNs) via the team bootstrap
CLI in `platform-tooling` — you do not need to clone or modify this repo directly. See
[Team onboarding](#team-onboarding).

## What's in this repo

```text
terraform/
├── platform/
│   ├── core/             # Stage 0 — S3 state bucket, GitHub OIDC provider, CI role (manual only)
│   ├── iam/              # Stage 1 — IAM deployer roles and governance controls
│   └── registry/         # Stage 2 — Shared ECR container registry
├── account-bootstrap/    # Run once per workload account — creates cross-account deployer role
├── environments/
│   └── dev/              # Stage 3 — Dev environment (deployed cross-account into dev AWS account)
├── modules/
│   └── aws/
│       └── ecr/          # Reusable ECR repository module
└── policies/
    └── iam/              # OPA/Conftest policy gates (enforced in CI)

scripts/
└── bootstrap.py  # Guided one-time setup CLI
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.10
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) ≥ 2.x, configured with credentials for the **shared-services account**. For the first-ever bootstrap, use an admin SSO permission set. For subsequent re-runs of `apply-core`, use the `platform-bootstrap` IAM role (see [Re-running apply-core](#re-running-apply-core))
- [gh CLI](https://cli.github.com/) ≥ 2.x, authenticated (`gh auth login`)
- [uv](https://docs.astral.sh/uv/) (runs the bootstrap CLI — installs Python and dependencies automatically)
- [pre-commit](https://pre-commit.com/) (optional but recommended — regenerates lock files automatically on commit):

  ```bash
  pip install pre-commit
  pre-commit install
  ```

- A local `terraform/platform/core/terraform.tfvars` (gitignored — copy from the example and fill in your GitHub org):

  ```bash
  cp terraform/platform/core/terraform.tfvars.example terraform/platform/core/terraform.tfvars
  ```

  Set `github_org` to your GitHub username or organisation name.

- Fill in `terraform/platform/registry/registry.auto.tfvars` (committed — edit it directly):
  set `github_org`, list the repositories allowed to push images (`github_allowed_repos`),
  and define the ECR repositories to create (`repositories`). This file is loaded
  automatically by both CI and local runs — commit it once the values are correct.

## Getting started

There is a deliberate four-stage apply order. Use the bootstrap CLI to run all steps in one guided sequence:

```bash
uv run scripts/bootstrap.py run
```

Each step validates that the previous stage deployed correctly before proceeding — if
any AWS resource or GitHub configuration is missing, the CLI stops and tells you what
to fix. Run all checks independently at any time:

```bash
uv run scripts/bootstrap.py validate
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

See [terraform/platform/core/README.md](terraform/platform/core/README.md)
for full details, including the manual process if you prefer not to use the CLI.

### Stage 1 — IAM deployer roles

After core is applied, migrate the `iam` environment state to S3:

```bash
uv run scripts/bootstrap.py migrate-state iam
```

From this point on, `iam` is applied automatically by CI on every merge to `main`
(with a required reviewer gate for the `iam-production` GitHub Environment).

See [terraform/platform/iam/README.md](terraform/platform/iam/README.md)
for full details, including how to add a team role.

### Stage 2 — shared registry

After iam is applied, migrate the `registry` stack state to S3:

```bash
uv run scripts/bootstrap.py migrate-state registry
```

From this point on, `registry` is applied automatically by CI on every merge to `main`.

### Stage 3 — dev environment

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

## Post-bootstrap GitHub setup

Two manual steps are required before CI can gate and apply changes correctly.
The bootstrap CLI prints a reminder at the end of `run`, but they cannot be
automated via the `gh` CLI.

### 1. Create the `iam-production` GitHub Environment

The `apply-iam` CI job is gated by this environment — it pauses for a required
reviewer before applying any IAM changes.

1. Go to **Settings → Environments → New environment** in your repository.
2. Name it `iam-production`.
3. Add required reviewers (platform team GitHub handles).
4. Save.

### 2. Enable branch protection on `main`

Require the following status checks to pass before merging:

- `fmt`
- `validate-iam`, `validate-registry`, `validate-dev`
- `plan-iam`, `plan-registry`, `plan-dev`

Also enable **Require pull request reviews** to enforce CODEOWNERS.

Go to **Settings → Branches → Add rule** and target the `main` branch.

## Re-running apply-core

After the initial bootstrap, the `platform-bootstrap` IAM role (created by `iam/`) provides
the minimum permissions needed to re-run `apply-core` without admin credentials.

**1. Get the role ARN** from the `iam/` Terraform outputs:

```bash
cd terraform/platform/iam
terraform output platform_bootstrap_role_arn
```

**2. Add a named profile to `~/.aws/config`:**

```ini
[profile platform-bootstrap]
role_arn          = <role ARN from step 1>
source_profile    = <your SSO profile name>
role_session_name = platform-bootstrap
```

**3. Run the bootstrap under that profile:**

```bash
AWS_PROFILE=platform-bootstrap uv run scripts/bootstrap.py apply-core
```

The `source_profile` must be an SSO profile whose underlying IAM principal has `sts:AssumeRole`
permission for the `platform-bootstrap` role. This is controlled by `var.trusted_principal_arns`
in `iam/` (defaults to allowing any principal in the account).

## CI/CD

After bootstrap, pull requests trigger:

- **fmt** — `terraform fmt -check`
- **lock-files** — verifies `.terraform.lock.hcl` files cover all target platforms
- **validate-iam / validate-registry / validate-dev** — syntax validation (no AWS credentials needed)
- **plan-iam** — plan with OPA/Conftest policy gate (path-filtered to `platform/iam/**`)
- **plan-registry** — plan (path-filtered to `platform/registry/**` or `modules/**`)
- **plan-dev** — plan (path-filtered to `environments/dev/**`)

Merges to `main` trigger:

- **apply-iam** — pauses for required reviewer approval (`iam-production` environment)
- **apply-registry** — runs after `apply-iam` succeeds
- **apply-dev** — runs after `apply-registry` succeeds

See [.github/workflows/terraform.yml](.github/workflows/terraform.yml) for the full workflow.

## Adding a team IAM role

Teams request a dedicated Terraform deployer role by opening a pull request.
See [terraform/platform/iam/README.md](terraform/platform/iam/README.md#adding-a-team-role).

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

## Updating providers

Lock files are committed for all environments. They pin provider versions and include
checksums for `linux_amd64`, `darwin_arm64`, and `darwin_amd64` so CI does not need
to re-download or modify them at runtime.

When bumping a provider version, regenerate the lock file for all target platforms:

```bash
cd terraform/platform/<stack>       # or terraform/environments/<env>
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64 \
  -platform=darwin_amd64
```

Commit the updated `.terraform.lock.hcl` alongside the version change.

If you have `pre-commit` installed, this runs automatically on `git commit` for any
environment whose lock file has changed. Pull requests are also gated by a `lock-files`
CI job that fails if the committed lock files do not match the regenerated output.

To bypass the hook for a work-in-progress commit, use `git commit --no-verify`. The
`lock-files` CI job still enforces correctness on the PR.

## Adding a workload account (dev, staging, prod)

Each environment runs in its own AWS account. After creating the account via
Control Tower Account Factory, bootstrap it with:

```bash
uv run scripts/bootstrap.py bootstrap-account --account-id <id> --env <env>
```

The CLI prints the exact next steps, including:

1. Adding the account ID to `workload_account_ids` in `platform/core/terraform.tfvars`
   (this file is gitignored — edit it locally), then re-applying `platform/core/`
   with the `platform-bootstrap` role so `ci-pipeline` gains `sts:AssumeRole`
   permission for the new account:

   ```bash
   AWS_PROFILE=platform-bootstrap uv run scripts/bootstrap.py apply-core
   ```

2. Setting the deployer role ARN as a GitHub Actions secret so CI can assume it:

   ```bash
   gh secret set TERRAFORM_DEPLOYER_<ENV>_ARN --body "<deployer_role_arn>"
   ```

   **This secret must be set before running `validate`** — the validate command checks
   for it and will fail with a clear message if it is missing.

See [docs/multi-account.md](docs/multi-account.md) for the full walkthrough.

## Further reading

- [Multi-Account Architecture](docs/multi-account.md) — account structure, trust chain,
  and how to add new workload accounts
- [IAM Governance](docs/iam-governance.md) — governance patterns, auditing strategy,
  and the rationale behind key design decisions
