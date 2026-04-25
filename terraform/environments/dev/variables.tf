variable "aws_region" {
  type    = string
  default = "ap-east-1"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "terraform_role_arn" {
  description = "ARN of the IAM role for Terraform to assume when deploying this environment. Created by platform/iam. Leave empty to use current credentials directly."
  type        = string
  default     = ""
}
