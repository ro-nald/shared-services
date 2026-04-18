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

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
