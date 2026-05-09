# -----------------------------------------------------------------------------
# registry — Shared container registry
#
# Requires platform/core/ and platform/iam/ to have been applied first. Owns all ECR
# repositories and the GitHub Actions push role. Shared across all environments
# — images are built once and promoted by tag/digest, not copied between repos.
#
# In CI this stack is applied by the ci-pipeline role (created in core/).
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  dynamic "assume_role" {
    for_each = var.local_deployer_role_arn != "" ? [var.local_deployer_role_arn] : []
    content {
      role_arn     = assume_role.value
      session_name = "terraform-registry"
    }
  }
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket = "shared-services-tfstate-${data.aws_caller_identity.current.account_id}"
    key    = "core/terraform.tfstate"
    region = var.aws_region
  }
}

# GitHub OIDC provider is created in platform/core — do not recreate it here.
module "ecr" {
  source = "../../modules/aws/ecr"

  aws_region                  = var.aws_region
  github_org                  = var.github_org
  github_allowed_repos        = var.github_allowed_repos
  repositories                = var.repositories
  tags                        = var.tags
  create_github_oidc_provider = false
}
