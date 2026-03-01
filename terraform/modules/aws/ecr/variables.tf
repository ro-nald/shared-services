variable "aws_region" {
  description = "AWS region where ECR repositories will be created"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organisation name (e.g. 'my-org')"
  type        = string
}

variable "github_allowed_repos" {
  description = <<-EOT
    GitHub repositories (relative to github_org) that are allowed to push
    images. Wildcards are supported (e.g. \"*\" grants all repos in the org).
  EOT
  type        = list(string)
  # Example: ["service-a", "service-b", "*"]
}

variable "repositories" {
  description = <<-EOT
    Map of ECR repositories to create.
    Key   = repository name (becomes the ECR repo name).
    Value = optional per-repo overrides.
  EOT
  type = map(object({
    # Keep this many tagged images per repo
    tagged_image_count = optional(number, 10)
    # Scan on push
    scan_on_push = optional(bool, true)
    # image_tag_mutability: "MUTABLE" or "IMMUTABLE"
    image_tag_mutability = optional(string, "IMMUTABLE")
  }))
}

variable "create_github_oidc_provider" {
  description = <<-EOT
    Set to false if a GitHub OIDC provider already exists in this AWS account
    (only one can exist per account).
  EOT
  type    = bool
  default = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
