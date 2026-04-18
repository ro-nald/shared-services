# -----------------------------------------------------------------------------
# STAGE 0 — core bootstrap (manual only — never applied by CI)
#
# Apply once with admin credentials. Creates:
#   - S3 state bucket shared by all environments
#   - GitHub OIDC identity provider
#   - ci-pipeline IAM role used by GitHub Actions
#
# Use the bootstrap CLI to apply and migrate state in one guided sequence:
#   uv run scripts/bootstrap.py apply-core
#
# See README.md for manual steps if you prefer not to use the CLI.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Initially uses local state. The bootstrap CLI migrates core state to S3
  # after the bucket is created. Do not edit this block manually — the CLI
  # generates backend.hcl and runs `terraform init -migrate-state`.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
