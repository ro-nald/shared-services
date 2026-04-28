variable "aws_region" {
  description = "AWS region for the provider"
  type        = string
  default     = "ap-east-1"
}

variable "target_account_id" {
  description = "AWS account ID of the workload account being bootstrapped"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod). Used to name the deployer role."
  type        = string
}

variable "shared_services_account_id" {
  description = "AWS account ID of the shared-services account where ci-pipeline lives"
  type        = string
}

variable "additional_trusted_arns" {
  description = <<-EOT
    Additional IAM principal ARNs that can assume the deployer role (e.g. IAM
    Identity Center role ARNs for human access). ci-pipeline is always trusted.
  EOT
  type    = list(string)
  default = []
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
  }
}
