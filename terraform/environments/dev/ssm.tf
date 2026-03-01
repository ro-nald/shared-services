# -----------------------------------------------------------------------------
# Shared-services SSM outputs (dev tier)
#
# Published after every apply so that team bootstrap CLIs can read platform
# values without requiring direct access to Terraform state. All parameters
# live under the opaque SSM namespace GUID to prevent path enumeration.
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "ecr_push_role_arn" {
  name  = "/shared-services/${var.ssm_namespace_id}/dev/ecr-push-role-arn"
  type  = "String"
  value = module.ecr.github_actions_role_arn

  tags = var.tags
}

resource "aws_ssm_parameter" "github_oidc_provider_arn" {
  name  = "/shared-services/${var.ssm_namespace_id}/dev/github-oidc-provider-arn"
  type  = "String"
  value = module.ecr.github_oidc_provider_arn

  tags = var.tags
}

resource "aws_ssm_parameter" "ecr_url" {
  for_each = module.ecr.repository_urls

  # Sanitise ECR repo names: replace "/" with "--" so the path remains valid.
  # e.g. "dev/service-a" → parameter name "dev--service-a"
  name  = "/shared-services/${var.ssm_namespace_id}/dev/ecr/${replace(each.key, "/", "--")}"
  type  = "String"
  value = each.value

  tags = var.tags
}
