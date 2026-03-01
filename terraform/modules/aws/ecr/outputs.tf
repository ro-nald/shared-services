output "repository_urls" {
  description = "Map of repository name → ECR URL"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository name → ECR ARN"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.arn
  }
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role GitHub Actions should assume"
  value       = aws_iam_role.github_ecr_push.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (null if not created here)"
  value       = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : null
}
