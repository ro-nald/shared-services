variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-east-1"
}

variable "github_org" {
  description = "GitHub organisation that owns this repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
  default     = "shared-services"
}

variable "workload_account_ids" {
  description = <<-EOT
    AWS account IDs of workload accounts (dev, staging, prod) that the
    ci-pipeline role is permitted to assume terraform-deployer-* roles in.
    Add each account ID here after bootstrapping it with:
      uv run scripts/bootstrap.py bootstrap-account --account-id <id> --env <env>
  EOT
  type    = list(string)
  default = []
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
