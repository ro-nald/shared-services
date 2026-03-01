terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend values are supplied via backend.hcl (local) or -backend-config
  # flags (CI). Do not add values here — this block must remain empty so the
  # repository stays template-pure.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  # STAGE 2: set terraform_role_arn (in terraform.tfvars or via -var) to have
  # Terraform assume the deployer role created in environments/iam.
  # Leave empty to use the current credentials directly (e.g. during bootstrap).
  dynamic "assume_role" {
    for_each = var.terraform_role_arn != "" ? [var.terraform_role_arn] : []
    content {
      role_arn     = assume_role.value
      session_name = "terraform-dev"
    }
  }
}

module "ecr" {
  source = "../../modules/aws/ecr"

  aws_region           = var.aws_region
  github_org           = var.github_org
  github_allowed_repos = var.github_allowed_repos
  repositories         = var.repositories
  tags                 = var.tags
  create_github_oidc_provider = false
}
