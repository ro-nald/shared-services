# -----------------------------------------------------------------------------
# Shared-services SSM outputs — registry
#
# Published after every apply so that team bootstrap CLIs and environment stacks
# can discover ECR URLs and the push role ARN without accessing Terraform state.
# All parameters live under the opaque SSM namespace GUID.
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "ecr_push_role_arn" {
  name  = "/shared-services/${data.terraform_remote_state.core.outputs.ssm_namespace_id}/registry/ecr-push-role-arn"
  type  = "String"
  value = module.ecr.github_actions_role_arn

  tags = var.tags
}

resource "aws_ssm_parameter" "ecr_url" {
  for_each = module.ecr.repository_urls

  name  = "/shared-services/${data.terraform_remote_state.core.outputs.ssm_namespace_id}/registry/ecr/${replace(each.key, "/", "--")}"
  type  = "String"
  value = each.value

  tags = var.tags
}
