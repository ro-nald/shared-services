output "ssm_namespace_id" {
  description = "6-character hex namespace ID for all shared-services SSM parameters"
  value       = random_id.ssm_namespace.hex
}

output "state_bucket_name" {
  description = "Name of the S3 bucket storing Terraform state for all environments"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "ci_pipeline_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions CI"
  value       = aws_iam_role.ci_pipeline.arn
}

output "next_steps" {
  description = "Steps to complete after applying core"
  value       = <<-EOT

    Core applied. Complete the bootstrap with:

      uv run scripts/bootstrap.py apply-core   # migrates core state to S3, then:
      uv run scripts/bootstrap.py migrate-state iam
      uv run scripts/bootstrap.py migrate-state dev
      uv run scripts/bootstrap.py configure-github

    Or run all steps at once:

      uv run scripts/bootstrap.py run

    Then manually:
      1. Create a GitHub Environment named 'iam-production' with required reviewers
      2. Enable branch protection on main (required status checks + PR reviews)
  EOT
}
