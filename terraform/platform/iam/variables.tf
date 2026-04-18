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

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
