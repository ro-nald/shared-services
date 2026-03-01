output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "terraform_deployer_dev_role_arn" {
  description = "ARN of the Terraform deployer role for the dev environment"
  value       = aws_iam_role.terraform_deployer_dev.arn
}

output "next_steps" {
  description = <<-EOT
    Use the role-picker CLI (separate repo) to discover and select a deployer role,
    then proceed via one of the two paths below.

    PATH A — TFVars (recommended, credentials never enter the shell):
      In environments/dev/terraform.tfvars set:
        terraform_role_arn = "<role_arn>"
      Then run: terraform apply

    PATH B — Named AWS profile:
      Add to ~/.aws/config:
        [profile terraform-dev]
        role_arn          = <role_arn>
        source_profile    = default
        role_session_name = terraform-dev
      Then run: AWS_PROFILE=terraform-dev terraform apply
  EOT
  value = "Run the role-picker CLI to select a role, then follow PATH A or PATH B above."
}
