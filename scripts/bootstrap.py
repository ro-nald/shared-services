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
  1. apply-core   — apply environments/core, migrate its state to S3
  2. migrate-state iam / dev — migrate each environment's state to S3
  3. configure-github — write GitHub Variable and Secret via gh CLI

Run all steps at once:
  uv run scripts/bootstrap.py run

Or check where you are:
  uv run scripts/bootstrap.py status
"""

import json
import os
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
CORE_DIR = REPO_ROOT / "terraform" / "environments" / "core"
IAM_DIR = REPO_ROOT / "terraform" / "environments" / "iam"
DEV_DIR = REPO_ROOT / "terraform" / "environments" / "dev"
STATE_FILE = REPO_ROOT / "scripts" / ".bootstrap-state.json"

ENV_DIRS = {
    "iam": IAM_DIR,
    "dev": DEV_DIR,
    "core": CORE_DIR,
}

ENV_KEYS = {
    "iam": "iam/terraform.tfstate",
    "dev": "dev/terraform.tfstate",
    "core": "core/terraform.tfstate",
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
    data["applied_at"] = datetime.now(timezone.utc).isoformat()
    STATE_FILE.write_text(json.dumps(data, indent=2) + "\n")


def write_backend_hcl(env, bucket, region="ap-east-1"):
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
    # SSH: git@github.com:owner/repo.git
    # HTTPS: https://github.com/owner/repo.git
    match = re.search(r"[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    return match.group(1) if match else None


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

    # Working directory
    is_repo_root = (REPO_ROOT / "terraform").is_dir() and (REPO_ROOT / "scripts").is_dir()
    checks.append(("Repo root", is_repo_root, str(REPO_ROOT)))

    # Terraform >= 1.10
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

    # AWS credentials
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

    # gh CLI >= 2.x
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


@cli.command("apply-core")
def apply_core():
    """Apply environments/core and migrate its state to S3."""
    console.rule("[bold]Step 1 — apply-core[/bold]")

    _run_checks(abort_on_fail=True)

    console.print("\n[bold]Initialising core (local backend)...[/bold]")
    run(["terraform", "-chdir=terraform/environments/core", "init"])

    console.print("\n[bold]Planning core...[/bold]")
    run(["terraform", "-chdir=terraform/environments/core", "plan"])

    if not click.confirm("\nApply the above plan?", default=False):
        console.print("Aborted.")
        sys.exit(0)

    console.print("\n[bold]Applying core...[/bold]")
    run(["terraform", "-chdir=terraform/environments/core", "apply", "-auto-approve"])

    console.print("\n[bold]Reading outputs...[/bold]")
    result = run(
        ["terraform", "-chdir=terraform/environments/core", "output", "-json"],
        capture=True,
    )
    outputs = json.loads(result.stdout)
    bucket = outputs["state_bucket_name"]["value"]
    ci_role_arn = outputs["ci_pipeline_role_arn"]["value"]
    ssm_namespace_id = outputs["ssm_namespace_id"]["value"]

    console.print(f"  state_bucket_name    = {bucket}")
    console.print(f"  ci_pipeline_role_arn = {ci_role_arn}")
    console.print(f"  ssm_namespace_id     = {ssm_namespace_id}")

    console.print("\n[bold]Writing core/backend.hcl...[/bold]")
    hcl_path = write_backend_hcl("core", bucket)
    console.print(f"  Written: {hcl_path.relative_to(REPO_ROOT)}")

    console.print("\n[bold]Migrating core state to S3...[/bold]")
    run(
        [
            "terraform",
            "-chdir=terraform/environments/core",
            "init",
            "-migrate-state",
            "-backend-config=backend.hcl",
        ]
    )

    save_state({"state_bucket_name": bucket, "ci_pipeline_role_arn": ci_role_arn, "ssm_namespace_id": ssm_namespace_id})
    console.print(f"\n  Bootstrap state saved to {STATE_FILE.relative_to(REPO_ROOT)}")
    console.print("\n[green]✓ core applied and state migrated to S3.[/green]")


@cli.command("migrate-state")
@click.argument("env", type=click.Choice(["iam", "dev"]))
def migrate_state(env):
    """Migrate an environment's local state to S3. ENV is 'iam' or 'dev'."""
    console.rule(f"[bold]Migrate state — {env}[/bold]")

    state = load_state()
    if not state:
        console.print("[red]Error: run 'apply-core' first.[/red]")
        sys.exit(1)

    bucket = state["state_bucket_name"]

    console.print(f"\n[bold]Writing {env}/backend.hcl...[/bold]")
    hcl_path = write_backend_hcl(env, bucket)
    console.print(f"  Written: {hcl_path.relative_to(REPO_ROOT)}")

    console.print(f"\n[bold]Migrating {env} state to S3...[/bold]")
    run(
        [
            "terraform",
            f"-chdir=terraform/environments/{env}",
            "init",
            "-migrate-state",
            "-backend-config=backend.hcl",
        ]
    )

    console.print(f"\n[green]✓ {env} state migrated to S3.[/green]")


@cli.command("configure-github")
def configure_github():
    """Write GitHub Variable and Secret to the repository via gh CLI."""
    console.rule("[bold]Configure GitHub[/bold]")

    state = load_state()
    if not state:
        console.print("[red]Error: run 'apply-core' first.[/red]")
        sys.exit(1)

    bucket = state["state_bucket_name"]
    ci_role_arn = state["ci_pipeline_role_arn"]
    ssm_namespace_id = state.get("ssm_namespace_id", "")

    repo = git_remote_repo()
    if not repo:
        repo = click.prompt("Could not detect repo from git remote. Enter 'owner/repo'")

    console.print(f"\n  Repository: {repo}")

    # Check gh auth status; prompt login if needed
    auth_result = run("gh auth status", capture=True, check=False)
    if auth_result.returncode != 0:
        console.print("\n[yellow]gh CLI is not authenticated. Launching gh auth login...[/yellow]")
        run("gh auth login", check=True)

    console.print("\n[bold]Setting GitHub Variable TF_STATE_BUCKET...[/bold]")
    run(["gh", "variable", "set", "TF_STATE_BUCKET", "--body", bucket, "--repo", repo])
    console.print(f"  TF_STATE_BUCKET = {bucket}")

    console.print("\n[bold]Setting GitHub Variable SSM_NAMESPACE...[/bold]")
    if ssm_namespace_id:
        run(["gh", "variable", "set", "SSM_NAMESPACE", "--body", ssm_namespace_id, "--repo", repo])
        console.print(f"  SSM_NAMESPACE = {ssm_namespace_id}")
    else:
        console.print("[yellow]  SSM_NAMESPACE skipped — re-run apply-core to generate the GUID.[/yellow]")

    console.print("\n[bold]Setting GitHub Secret CI_PIPELINE_ROLE_ARN...[/bold]")
    run(["gh", "secret", "set", "CI_PIPELINE_ROLE_ARN", "--body", ci_role_arn, "--repo", repo])
    console.print(f"  CI_PIPELINE_ROLE_ARN = {ci_role_arn}")

    console.print(f"\n[green]✓ GitHub Variable and Secret written to {repo}.[/green]")


@cli.command("run")
def run_all():
    """Run the full bootstrap sequence with confirmation prompts."""
    console.rule("[bold]Shared-services bootstrap[/bold]")
    console.print("This will run: check → apply-core → migrate-state iam → migrate-state dev → configure-github\n")

    ctx = click.get_current_context()

    ctx.invoke(apply_core)

    console.print()
    if not click.confirm("Migrate iam state to S3?", default=True):
        console.print("Skipped. Run 'migrate-state iam' later.")
    else:
        ctx.invoke(migrate_state, env="iam")

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
    console.print("[green]✓ dev state migrated to S3[/green]")
    if state:
        console.print(f"[green]✓ GitHub Variable and Secret written to {repo}[/green]")

    console.print("\n[bold]Next steps (manual — cannot be automated):[/bold]\n")
    console.print("  1. Create GitHub Environment:")
    console.print("       Name:      iam-production")
    console.print("       Reviewers: <platform team GitHub handles>")
    console.print(f"       URL:       https://github.com/{repo}/settings/environments\n")
    console.print("  2. Enable branch protection on main:")
    console.print("       Required status checks: fmt, validate-iam, validate-dev, plan-iam, plan-dev")
    console.print("       Require pull request reviews: yes (enforces CODEOWNERS)")


@cli.command("status")
def status():
    """Show current bootstrap progress and remaining steps."""
    console.rule("[bold]Bootstrap status[/bold]")

    state = load_state()

    table = Table(show_header=True, header_style="bold")
    table.add_column("Step")
    table.add_column("Status")
    table.add_column("Detail")

    # Bootstrap state file
    if state:
        detail = f"bucket: {state.get('state_bucket_name', '?')}"
        table.add_row("core applied", "[green]✓ done[/green]", detail)
    else:
        table.add_row("core applied", "[yellow]pending[/yellow]", "run apply-core")

    # backend.hcl files
    for env in ("core", "iam", "dev"):
        hcl = ENV_DIRS[env] / "backend.hcl"
        if hcl.exists():
            table.add_row(f"{env}/backend.hcl", "[green]✓ exists[/green]", str(hcl.relative_to(REPO_ROOT)))
        else:
            table.add_row(f"{env}/backend.hcl", "[yellow]missing[/yellow]", "not yet generated")

    # S3 bucket accessibility
    if state and state.get("state_bucket_name"):
        bucket = state["state_bucket_name"]
        s3_result = run(
            ["aws", "s3", "ls", f"s3://{bucket}"],
            capture=True,
            check=False,
        )
        if s3_result.returncode == 0:
            table.add_row("S3 bucket", "[green]✓ accessible[/green]", bucket)
        else:
            table.add_row("S3 bucket", "[red]✗ not accessible[/red]", bucket)
    else:
        table.add_row("S3 bucket", "[yellow]unknown[/yellow]", "apply-core first")

    # gh auth
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
