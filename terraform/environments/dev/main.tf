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
  # Terraform assume the deployer role created in platform/iam.
  # Leave empty to use the current credentials directly (e.g. during bootstrap).
  dynamic "assume_role" {
    for_each = var.terraform_role_arn != "" ? [var.terraform_role_arn] : []
    content {
      role_arn     = assume_role.value
      session_name = "terraform-dev"
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

