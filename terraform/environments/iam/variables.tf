variable "aws_region" {
  description = "AWS region for the provider (IAM is global, but the provider still needs a region)"
  type        = string
  default     = "ap-east-1"
}

variable "trusted_principal_arns" {
  description = <<-EOT
    IAM principal ARNs allowed to assume the Terraform deployer roles.
    Leave empty (default) to fall back to the account root, which means any
    IAM entity in the account that has been explicitly granted sts:AssumeRole
    on the target role ARN can assume it.

    Example override:
      trusted_principal_arns = [
        "arn:aws:iam::123456789012:user/alice",
        "arn:aws:iam::123456789012:role/ci-runner",
      ]
  EOT
  type    = list(string)
  default = []
}

variable "ssm_namespace_id" {
  description = "6-character hex namespace ID for SSM parameters published by shared-services (from core outputs)"
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the S3 state bucket (from core outputs). Used to scope team S3 permissions to teams/* prefix only."
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
