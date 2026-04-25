output "repository_urls" {
  description = "Map of repository name → ECR URL"
  value       = module.ecr.repository_urls
}

output "repository_arns" {
  description = "Map of repository name → ECR ARN"
  value       = module.ecr.repository_arns
}

output "github_actions_role_arn" {
  description = "ARN for GitHub Actions workflows to assume when pushing images"
  value       = module.ecr.github_actions_role_arn
}
