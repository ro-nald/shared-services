variable "aws_region" {
  type    = string
  default = "ap-east-1"
}

variable "github_org" {
  type = string
}

variable "github_allowed_repos" {
  type = list(string)
}

variable "repositories" {
  type = map(object({
    tagged_image_count   = optional(number, 10)
    scan_on_push         = optional(bool, true)
    image_tag_mutability = optional(string, "IMMUTABLE")
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "terraform_role_arn" {
  description = <<-EOT
    ARN of the IAM role for Terraform to assume when deploying this environment.
    Created by environments/iam. Leave empty to use the current credentials directly.
  EOT
  type    = string
  default = ""
}
