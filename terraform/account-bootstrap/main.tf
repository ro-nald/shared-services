# -----------------------------------------------------------------------------
# account-bootstrap — one-time setup for a new workload account
#
# Creates terraform-deployer-<env> in the target account, trusting
# ci-pipeline from the shared-services account to assume it.
#
# Applied once per workload account using OrganizationAccountAccessRole:
#   uv run scripts/bootstrap.py bootstrap-account \
#     --account-id <target-account-id> \
#     --env <env-name>
#
# State is stored locally. Keep the generated terraform.tfstate file in a
# private location (e.g. encrypted storage or a private S3 bucket).
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.target_account_id}:role/OrganizationAccountAccessRole"
    session_name = "account-bootstrap"
  }
}

data "aws_caller_identity" "current" {}
