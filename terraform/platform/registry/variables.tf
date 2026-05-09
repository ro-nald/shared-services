variable "aws_region" {
  type    = string
  default = "ap-east-1"
}

variable "github_org" {
  description = "GitHub organisation name (e.g. 'my-org')"
  type        = string
}

variable "github_allowed_repos" {
  description = "Repositories allowed to push images. Wildcards supported (e.g. \"*\" for all repos in the org)."
  type        = list(string)
}

variable "repositories" {
  description = <<-EOT
    ECR repositories to create. Keys are repository names (environment-agnostic —
    no env prefix). The same image is promoted across environments by tag or digest.
  EOT
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

variable "local_deployer_role_arn" {
  description = "ARN of the terraform-deployer-registry role to assume for local runs. Leave empty (default) to use current credentials — CI uses ci-pipeline directly and does not set this."
  type        = string
  default     = ""
}
