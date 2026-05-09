output "deployer_role_arn" {
  description = "ARN of the terraform-deployer-<env> role created in the workload account"
  value       = aws_iam_role.deployer.arn
}

output "next_steps" {
  description = "Steps to complete after applying this stack"
  value       = <<-EOT
    1. Add ${var.target_account_id} to workload_account_ids in
       terraform/platform/core/terraform.tfvars, then re-apply platform/core
       (or let CI apply it) so ci-pipeline gains sts:AssumeRole permission.

    2. Set the deployer role ARN as a GitHub Actions secret:
         gh secret set TERRAFORM_DEPLOYER_${upper(var.environment)}_ARN \
           --body "${aws_iam_role.deployer.arn}"
       CI reads this secret as TF_VAR_terraform_role_arn to assume the role.

    3. For human (local) access, add a named profile to ~/.aws/config:
         [profile terraform-${var.environment}]
         role_arn          = ${aws_iam_role.deployer.arn}
         source_profile    = <your-sso-profile>
         role_session_name = terraform-${var.environment}
  EOT
}
