#!/usr/bin/env python3
# /// script
# dependencies = [
#   "click>=8.0",
#   "rich>=13.0",
# ]
# ///
"""
Bootstrap CLI for the shared-services Terraform repository.

Guides the one-time setup sequence:
  1. apply-core   — apply platform/core, migrate its state to S3
  2. migrate-state iam / registry / dev — migrate each environment's state to S3
  3. configure-github — write GitHub Variable and Secret via gh CLI

All commands are idempotent: re-running a completed step is safe. Each step
refreshes local state from AWS so the JSON stays current even if steps were
completed outside this CLI.

Run all steps at once:
  uv run scripts/bootstrap.py run

Check where you are:
  uv run scripts/bootstrap.py status

Sync local state file with actual AWS state:
  uv run scripts/bootstrap.py refresh
"""

import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import click
from rich.console import Console
from rich.table import Table

console = Console()

# ---------------------------------------------------------------------------
# Paths (all relative to the repo root)
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
CORE_DIR = REPO_ROOT / "terraform" / "platform" / "core"
IAM_DIR = REPO_ROOT / "terraform" / "platform" / "iam"
REGISTRY_DIR = REPO_ROOT / "terraform" / "platform" / "registry"
DEV_DIR = REPO_ROOT / "terraform" / "environments" / "dev"
ACCOUNT_BOOTSTRAP_DIR = REPO_ROOT / "terraform" / "account-bootstrap"
STATE_FILE = REPO_ROOT / "scripts" / ".bootstrap-state.json"
CORE_OVERRIDE = CORE_DIR / "override.tf"

AWS_REGION = "ap-east-1"

ENV_DIRS = {
    "core": CORE_DIR,
    "iam": IAM_DIR,
    "registry": REGISTRY_DIR,
    "dev": DEV_DIR,
}

ENV_KEYS = {
    "core": "core/terraform.tfstate",
    "iam": "iam/terraform.tfstate",
    "registry": "registry/terraform.tfstate",
    "dev": "dev/terraform.tfstate",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def run(cmd, *, check=True, capture=False, cwd=None):
    """Run a shell command, streaming output unless capture=True."""
    result = subprocess.run(
        cmd,
        shell=isinstance(cmd, str),
        check=check,
        capture_output=capture,
        text=True,
        cwd=cwd or REPO_ROOT,
    )
    return result


def load_state():
    """Return the bootstrap state dict, or None if not yet written."""
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return None


def save_state(data):
    existing = load_state() or {}
    existing.update(data)
    existing["applied_at"] = datetime.now(timezone.utc).isoformat()
    STATE_FILE.write_text(json.dumps(existing, indent=2) + "\n")


def write_backend_hcl(env, bucket, region=AWS_REGION):
    """Write a backend.hcl file for the given environment."""
    path = ENV_DIRS[env] / "backend.hcl"
    path.write_text(
        f'bucket       = "{bucket}"\n'
        f'key          = "{ENV_KEYS[env]}"\n'
        f'region       = "{region}"\n'
        f"use_lockfile = true\n"
        f"encrypt      = true\n"
    )
    return path


def git_remote_repo():
    """Parse 'owner/repo' from git remote origin URL."""
    result = run("git remote get-url origin", capture=True, check=False)
    if result.returncode != 0:
        return None
    url = result.stdout.strip()
    # SSH: git@github.com:owner/repo.git  HTTPS: https://github.com/owner/repo.git
    match = re.search(r"[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    return match.group(1) if match else None


def _aws_account_id():
    """Return the current AWS account ID, or None if credentials unavailable."""
    result = run("aws sts get-caller-identity", capture=True, check=False)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)["Account"]
    except (json.JSONDecodeError, KeyError):
        return None


def _bucket_name(account_id):
    return f"shared-services-tfstate-{account_id}"


def _read_s3_state_outputs(bucket, key):
    """
    Read Terraform outputs from a state file stored in S3.
    Returns a flat dict {output_name: value} or None on failure.
    """
    result = run(
        ["aws", "s3", "cp", f"s3://{bucket}/{key}", "-", "--region", AWS_REGION],
        capture=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        state = json.loads(result.stdout)
        return {name: val.get("value") for name, val in state.get("outputs", {}).items()}
    except (json.JSONDecodeError, KeyError):
        return None


def _state_key_exists(bucket, key):
    """Return True if the given S3 key exists (i.e. state has been migrated)."""
    result = run(
        ["aws", "s3api", "head-object", "--bucket", bucket, "--key", key, "--region", AWS_REGION],
        capture=True,
        check=False,
    )
    return result.returncode == 0


def _refresh_state(silent=False):
    """
    Query AWS to rebuild bootstrap state from actual infrastructure.
    Updates .bootstrap-state.json when the S3 bucket and core state are found.
    Returns the refreshed state dict, or None if core hasn't been applied yet.
    """
    account_id = _aws_account_id()
    if not account_id:
        if not silent:
            console.print("[yellow]Refresh skipped: AWS credentials not available.[/yellow]")
        return None

    bucket = _bucket_name(account_id)

    bucket_ok = run(
        ["aws", "s3api", "head-bucket", "--bucket", bucket, "--region", AWS_REGION],
        capture=True,
        check=False,
    ).returncode == 0

    if not bucket_ok:
        return None

    outputs = _read_s3_state_outputs(bucket, ENV_KEYS["core"])
    if not outputs:
        return None

    refreshed = {
        "state_bucket_name": bucket,
        "ci_pipeline_role_arn": outputs.get("ci_pipeline_role_arn"),
        "ssm_namespace_id": outputs.get("ssm_namespace_id"),
    }

    existing = load_state() or {}
    changed_keys = [k for k, v in refreshed.items() if existing.get(k) != v]

    if changed_keys:
        save_state(refreshed)
        if not silent:
            console.print(f"[cyan]State refreshed from AWS (updated: {', '.join(changed_keys)})[/cyan]")
    elif not silent:
        console.print("[cyan]Local state matches AWS — no changes.[/cyan]")

    return load_state()


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


@click.group()
def cli():
    """Shared-services Terraform bootstrap CLI."""


@cli.command()
def check():
    """Verify prerequisites before running any bootstrap steps."""
    _run_checks(abort_on_fail=False)


def _run_checks(abort_on_fail=True):
    """Run all prerequisite checks. Returns True if all pass."""
    checks = []

    is_repo_root = (REPO_ROOT / "terraform").is_dir() and (REPO_ROOT / "scripts").is_dir()
    checks.append(("Repo root", is_repo_root, str(REPO_ROOT)))

    tf_result = run("terraform version -json", capture=True, check=False)
    tf_ok = False
    tf_detail = "not found"
    if tf_result.returncode == 0:
        try:
            tf_version = json.loads(tf_result.stdout)["terraform_version"]
            parts = [int(x) for x in tf_version.split(".")[:2]]
            tf_ok = parts >= [1, 10]
            tf_detail = tf_version
        except (KeyError, ValueError, json.JSONDecodeError):
            tf_detail = "version parse error"
    checks.append(("Terraform >= 1.10", tf_ok, tf_detail))

    aws_result = run("aws sts get-caller-identity", capture=True, check=False)
    aws_ok = aws_result.returncode == 0
    aws_detail = "not configured"
    if aws_ok:
        try:
            identity = json.loads(aws_result.stdout)
            aws_detail = identity.get("Arn", "ok")
        except json.JSONDecodeError:
            aws_detail = "ok"
    checks.append(("AWS credentials", aws_ok, aws_detail))

    gh_result = run("gh --version", capture=True, check=False)
    gh_ok = False
    gh_detail = "not found"
    if gh_result.returncode == 0:
        match = re.search(r"(\d+)\.(\d+)", gh_result.stdout)
        if match:
            major = int(match.group(1))
            gh_ok = major >= 2
            gh_detail = f"{match.group(1)}.{match.group(2)}"
    checks.append(("gh CLI >= 2.x", gh_ok, gh_detail))

    table = Table(show_header=True, header_style="bold")
    table.add_column("Check")
    table.add_column("Status")
    table.add_column("Detail")

    all_pass = True
    for name, ok, detail in checks:
        status = "[green]✓ pass[/green]" if ok else "[red]✗ fail[/red]"
        table.add_row(name, status, detail)
        if not ok:
            all_pass = False

    console.print(table)

    if not all_pass and abort_on_fail:
        console.print("[red]Prerequisites not met. Fix the failures above and re-run.[/red]")
        sys.exit(1)

    return all_pass


@cli.command()
def refresh():
    """Sync local bootstrap state with actual AWS infrastructure."""
    console.rule("[bold]Refresh bootstrap state[/bold]")
    state = _refresh_state(silent=False)
    if state is None:
        console.print(
            "[yellow]Core infrastructure not found in AWS. "
            "Has apply-core been run?[/yellow]"
        )


@cli.command("apply-core")
def apply_core():
    """Apply platform/core and migrate its state to S3."""
    console.rule("[bold]Step 1 — apply-core[/bold]")

    _run_checks(abort_on_fail=True)

    # Clean up any override left by a previous interrupted run.
    if CORE_OVERRIDE.exists():
        CORE_OVERRIDE.unlink()

    account_id = _aws_account_id()
    bucket = _bucket_name(account_id) if account_id else None

    if bucket and _state_key_exists(bucket, ENV_KEYS["core"]):
        console.print("[green]Core state already exists in S3 — skipping apply.[/green]")
        state = _refresh_state(silent=True)
        if not state:
            console.print(
                "[red]State key found in S3 but could not read outputs. "
                "Investigate manually.[/red]"
            )
            sys.exit(1)
        hcl_path = write_backend_hcl("core", state["state_bucket_name"])
        console.print(f"  backend.hcl: {hcl_path.relative_to(REPO_ROOT)}")
        core_chdir = f"-chdir={CORE_DIR.relative_to(REPO_ROOT)}"
        run(["terraform", core_chdir, "init", "-backend-config=backend.hcl"])
        console.print("\n[green]✓ apply-core already complete.[/green]")
        return

    CORE_OVERRIDE.write_text('terraform {\n  backend "local" {}\n}\n')

    core_chdir = f"-chdir={CORE_DIR.relative_to(REPO_ROOT)}"

    console.print("\n[bold]Initialising core (local backend)...[/bold]")
    run(["terraform", core_chdir, "init"])

    console.print("\n[bold]Planning core...[/bold]")
    run(["terraform", core_chdir, "plan"])

    if not click.confirm("\nApply the above plan?", default=False):
        CORE_OVERRIDE.unlink()
        console.print("Aborted.")
        sys.exit(0)

    console.print("\n[bold]Applying core...[/bold]")
    run(["terraform", core_chdir, "apply", "-auto-approve"])

    console.print("\n[bold]Reading outputs...[/bold]")
    result = run(["terraform", core_chdir, "output", "-json"], capture=True)
    outputs = json.loads(result.stdout)
    bucket = outputs["state_bucket_name"]["value"]
    ci_role_arn = outputs["ci_pipeline_role_arn"]["value"]
    ssm_namespace_id = outputs["ssm_namespace_id"]["value"]

    console.print(f"  state_bucket_name    = {bucket}")
    console.print(f"  ci_pipeline_role_arn = {ci_role_arn}")
    console.print(f"  ssm_namespace_id     = {ssm_namespace_id}")

    CORE_OVERRIDE.unlink()

    console.print("\n[bold]Writing core/backend.hcl...[/bold]")
    hcl_path = write_backend_hcl("core", bucket)
    console.print(f"  Written: {hcl_path.relative_to(REPO_ROOT)}")

    console.print("\n[bold]Migrating core state to S3...[/bold]")
    run(["terraform", core_chdir, "init", "-migrate-state", "-backend-config=backend.hcl"])

    save_state(
        {
            "state_bucket_name": bucket,
            "ci_pipeline_role_arn": ci_role_arn,
            "ssm_namespace_id": ssm_namespace_id,
        }
    )
    console.print(f"\n  Bootstrap state saved to {STATE_FILE.relative_to(REPO_ROOT)}")
    console.print("\n[green]✓ core applied and state migrated to S3.[/green]")


@cli.command("migrate-state")
@click.argument("env", type=click.Choice(["iam", "registry", "dev"]))
def migrate_state(env):
    """Migrate an environment's local state to S3. ENV is 'iam', 'registry', or 'dev'."""
    console.rule(f"[bold]Migrate state — {env}[/bold]")

    state = _refresh_state(silent=True) or load_state()
    if not state:
        console.print("[red]Error: run 'apply-core' first.[/red]")
        sys.exit(1)

    bucket = state["state_bucket_name"]
    env_chdir = f"-chdir={ENV_DIRS[env].relative_to(REPO_ROOT)}"

    hcl_path = write_backend_hcl(env, bucket)
    console.print(f"\n  backend.hcl written: {hcl_path.relative_to(REPO_ROOT)}")

    if _state_key_exists(bucket, ENV_KEYS[env]):
        console.print(
            f"[green]{env} state already in S3 — skipping migration, running init only.[/green]"
        )
        run(["terraform", env_chdir, "init", "-backend-config=backend.hcl"])
        console.print(f"\n[green]✓ {env} already migrated.[/green]")
        return

    console.print(f"\n[bold]Migrating {env} state to S3...[/bold]")
    run(["terraform", env_chdir, "init", "-migrate-state", "-backend-config=backend.hcl"])
    console.print(f"\n[green]✓ {env} state migrated to S3.[/green]")


@cli.command("configure-github")
def configure_github():
    """Write GitHub Variable and Secret to the repository via gh CLI."""
    console.rule("[bold]Configure GitHub[/bold]")

    state = _refresh_state(silent=True) or load_state()
    if not state:
        console.print("[red]Error: run 'apply-core' first.[/red]")
        sys.exit(1)

    bucket = state["state_bucket_name"]
    ci_role_arn = state["ci_pipeline_role_arn"]

    repo = git_remote_repo()
    if not repo:
        repo = click.prompt("Could not detect repo from git remote. Enter 'owner/repo'")

    console.print(f"\n  Repository: {repo}")

    auth_result = run("gh auth status", capture=True, check=False)
    if auth_result.returncode != 0:
        console.print("\n[yellow]gh CLI is not authenticated. Launching gh auth login...[/yellow]")
        run("gh auth login", check=True)

    console.print("\n[bold]Setting GitHub Variable TF_STATE_BUCKET...[/bold]")
    run(["gh", "variable", "set", "TF_STATE_BUCKET", "--body", bucket, "--repo", repo])
    console.print(f"  TF_STATE_BUCKET = {bucket}")

    console.print("\n[bold]Setting GitHub Secret CI_PIPELINE_ROLE_ARN...[/bold]")
    run(["gh", "secret", "set", "CI_PIPELINE_ROLE_ARN", "--body", ci_role_arn, "--repo", repo])
    console.print(f"  CI_PIPELINE_ROLE_ARN = {ci_role_arn}")

    console.print(f"\n[green]✓ GitHub Variable and Secret written to {repo}.[/green]")


@cli.command("bootstrap-account")
@click.option("--account-id", required=True, help="AWS account ID of the workload account")
@click.option("--env", required=True, help="Environment name (e.g. dev, staging, prod)")
def bootstrap_account(account_id, env):
    """Create terraform-deployer-<env> in a workload account via OrganizationAccountAccessRole."""
    console.rule(f"[bold]Bootstrap account — {env} ({account_id})[/bold]")

    state = _refresh_state(silent=True) or load_state()
    if not state:
        console.print("[red]Error: run 'apply-core' first to establish the shared-services account.[/red]")
        sys.exit(1)

    shared_services_account_id = _aws_account_id()
    if not shared_services_account_id:
        console.print("[red]Error: AWS credentials not available.[/red]")
        sys.exit(1)

    console.print(f"\n  Shared-services account : {shared_services_account_id}")
    console.print(f"  Target account          : {account_id}")
    console.print(f"  Environment             : {env}")

    # Verify OrganizationAccountAccessRole is assumable
    console.print("\n[bold]Verifying access to target account...[/bold]")
    result = run(
        [
            "aws", "sts", "assume-role",
            "--role-arn", f"arn:aws:iam::{account_id}:role/OrganizationAccountAccessRole",
            "--role-session-name", "account-bootstrap-check",
        ],
        capture=True,
        check=False,
    )
    if result.returncode != 0:
        console.print(
            f"[red]Cannot assume OrganizationAccountAccessRole in {account_id}.\n"
            "Ensure current credentials have Organizations access and the account exists.[/red]"
        )
        sys.exit(1)
    console.print("  [green]✓ OrganizationAccountAccessRole is assumable[/green]")

    chdir = f"-chdir={ACCOUNT_BOOTSTRAP_DIR.relative_to(REPO_ROOT)}"
    common_vars = [
        f"-var=target_account_id={account_id}",
        f"-var=environment={env}",
        f"-var=shared_services_account_id={shared_services_account_id}",
    ]

    console.print("\n[bold]Initialising account-bootstrap...[/bold]")
    run(["terraform", chdir, "init", "-reconfigure"])

    console.print("\n[bold]Planning...[/bold]")
    run(["terraform", chdir, "plan"] + common_vars)

    if not click.confirm(
        f"\nCreate terraform-deployer-{env} in account {account_id}?", default=False
    ):
        console.print("Aborted.")
        sys.exit(0)

    console.print("\n[bold]Applying...[/bold]")
    run(["terraform", chdir, "apply", "-auto-approve"] + common_vars)

    result = run(
        ["terraform", chdir, "output", "-raw", "deployer_role_arn"] + common_vars,
        capture=True,
    )
    role_arn = result.stdout.strip()

    console.print(f"\n  deployer_role_arn = {role_arn}")
    console.print(f"\n[green]✓ terraform-deployer-{env} created in {account_id}.[/green]")
    console.print("\n[bold]Next steps:[/bold]")
    console.print(
        f"  1. Add {account_id} to workload_account_ids in "
        "terraform/platform/core/terraform.tfvars and re-apply platform/core"
    )
    console.print(
        f"  2. Set TF_VAR_terraform_role_arn={role_arn} "
        f"in the CI workflow for the {env} environment"
    )


@cli.command("run")
def run_all():
    """Run the full bootstrap sequence with confirmation prompts."""
    console.rule("[bold]Shared-services bootstrap[/bold]")
    console.print(
        "This will run: check → apply-core → migrate-state iam → "
        "migrate-state registry → migrate-state dev → configure-github\n"
    )

    ctx = click.get_current_context()

    ctx.invoke(apply_core)

    console.print()
    if not click.confirm("Migrate iam state to S3?", default=True):
        console.print("Skipped. Run 'migrate-state iam' later.")
    else:
        ctx.invoke(migrate_state, env="iam")

    console.print()
    if not click.confirm("Migrate registry state to S3?", default=True):
        console.print("Skipped. Run 'migrate-state registry' later.")
    else:
        ctx.invoke(migrate_state, env="registry")

    console.print()
    if not click.confirm("Migrate dev state to S3?", default=True):
        console.print("Skipped. Run 'migrate-state dev' later.")
    else:
        ctx.invoke(migrate_state, env="dev")

    console.print()
    if not click.confirm("Configure GitHub Variable and Secret?", default=True):
        console.print("Skipped. Run 'configure-github' later.")
    else:
        ctx.invoke(configure_github)

    _print_summary()


def _print_summary():
    state = load_state()
    repo = git_remote_repo() or "<org>/shared-services"

    console.rule("[bold green]Bootstrap complete[/bold green]")

    console.print("\n[green]✓ core applied — state migrated to S3[/green]")
    console.print("[green]✓ iam state migrated to S3[/green]")
    console.print("[green]✓ registry state migrated to S3[/green]")
    console.print("[green]✓ dev state migrated to S3[/green]")
    if state:
        console.print(f"[green]✓ GitHub Variable and Secret written to {repo}[/green]")

    console.print("\n[bold]Next steps (manual — cannot be automated):[/bold]\n")
    console.print("  1. Create GitHub Environment:")
    console.print("       Name:      iam-production")
    console.print("       Reviewers: <platform team GitHub handles>")
    console.print(f"       URL:       https://github.com/{repo}/settings/environments\n")
    console.print("  2. Enable branch protection on main:")
    console.print(
        "       Required status checks: fmt, validate-iam, validate-registry, "
        "validate-dev, plan-iam, plan-registry, plan-dev"
    )
    console.print("       Require pull request reviews: yes (enforces CODEOWNERS)")


@cli.command("status")
def status():
    """Show current bootstrap progress and remaining steps."""
    console.rule("[bold]Bootstrap status[/bold]")

    state = _refresh_state(silent=True) or load_state()

    table = Table(show_header=True, header_style="bold")
    table.add_column("Step")
    table.add_column("Status")
    table.add_column("Detail")

    if state:
        detail = f"bucket: {state.get('state_bucket_name', '?')}"
        table.add_row("core applied", "[green]✓ done[/green]", detail)
    else:
        table.add_row("core applied", "[yellow]pending[/yellow]", "run apply-core")

    bucket = state.get("state_bucket_name") if state else None
    for env in ("core", "iam", "registry", "dev"):
        if bucket:
            if _state_key_exists(bucket, ENV_KEYS[env]):
                table.add_row(f"{env} state in S3", "[green]✓ exists[/green]", ENV_KEYS[env])
            else:
                hint = "run apply-core" if env == "core" else f"run migrate-state {env}"
                table.add_row(f"{env} state in S3", "[yellow]missing[/yellow]", hint)
        else:
            table.add_row(f"{env} state in S3", "[yellow]unknown[/yellow]", "apply-core first")

    for env in ("core", "iam", "registry", "dev"):
        hcl = ENV_DIRS[env] / "backend.hcl"
        if hcl.exists():
            table.add_row(
                f"{env}/backend.hcl", "[green]✓ exists[/green]", str(hcl.relative_to(REPO_ROOT))
            )
        else:
            table.add_row(f"{env}/backend.hcl", "[yellow]missing[/yellow]", "not yet generated")

    gh_result = run("gh auth status", capture=True, check=False)
    if gh_result.returncode == 0:
        table.add_row("gh CLI auth", "[green]✓ authenticated[/green]", "")
    else:
        table.add_row("gh CLI auth", "[yellow]not authenticated[/yellow]", "run: gh auth login")

    console.print(table)

    if not state:
        console.print("\n[bold]Next step:[/bold] uv run scripts/bootstrap.py apply-core")


if __name__ == "__main__":
    cli()
