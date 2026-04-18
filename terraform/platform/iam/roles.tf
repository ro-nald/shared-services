# -----------------------------------------------------------------------------
# Terraform deployer roles
#
# Each role is assumed by Terraform when deploying the corresponding
# environment. Permissions are scoped to exactly what that environment manages.
# -----------------------------------------------------------------------------

locals {
  # If no explicit ARNs are supplied, fall back to the account root. This
  # delegates the assume-role decision to each IAM principal's own policy —
  # any user/role in the account that has been granted sts:AssumeRole for the
  # target role ARN can assume it. Override with specific ARNs to lock down
  # further.
  effective_trusted_arns = length(var.trusted_principal_arns) > 0 ? var.trusted_principal_arns : [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
}

# ---------------------------------------------------------------------------
# Shared trust policy — same set of principals can assume any deployer role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "terraform_trust" {
  statement {
    sid     = "AllowExplicitPrincipals"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.effective_trusted_arns
    }
  }
}

# ---------------------------------------------------------------------------
# Team deployer permission boundary
#
# This policy is a hard ceiling on what any team deployer role can ever do,
# regardless of what policies are attached to it. AWS evaluates the boundary
# at runtime: effective permissions = role policy ∩ boundary.
#
# It covers the superset of all service areas teams are permitted to manage.
# Actions intentionally omitted: IAM user management, CloudTrail, AWS Config,
# billing/cost management, and cross-account actions.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "team_deployer_boundary" {
  statement {
    sid       = "BoundaryECR"
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["*"]
  }

  statement {
    sid     = "BoundaryS3TeamState"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.core.outputs.state_bucket_name}/teams/*",
      "arn:aws:s3:::${data.terraform_remote_state.core.outputs.state_bucket_name}",
    ]
  }

  statement {
    sid    = "BoundarySSMSharedRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/shared-services/${data.terraform_remote_state.core.outputs.ssm_namespace_id}/*",
    ]
  }

  statement {
    sid       = "BoundaryEC2VPC"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid    = "BoundaryIAMServiceRoles"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:DeleteOpenIDConnectProvider",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:SetDefaultPolicyVersion",
      "iam:TagOpenIDConnectProvider",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagOpenIDConnectProvider",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "BoundarySTS"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "BoundaryCloudWatch"
    effect    = "Allow"
    actions   = ["logs:*", "cloudwatch:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "team_deployer_boundary" {
  name        = "team-deployer-boundary"
  description = "Permission boundary applied to all team Terraform deployer roles"
  policy      = data.aws_iam_policy_document.team_deployer_boundary.json

  tags = var.tags
}

# ---------------------------------------------------------------------------
# dev — permissions for environments/dev
#
# Covers: ECR repositories + lifecycle policies, IAM OIDC provider and the
# GitHub Actions push role created by the ecr module.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "terraform_deployer_dev" {
  # ECR: full management of repositories, lifecycle policies, and images
  statement {
    sid       = "ECRFull"
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["*"]
  }

  # IAM: create/manage the OIDC provider and roles that the ECR module owns
  statement {
    sid    = "IAMManage"
    effect = "Allow"
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:AttachRolePolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:DeleteOpenIDConnectProvider",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:SetDefaultPolicyVersion",
      "iam:TagOpenIDConnectProvider",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagOpenIDConnectProvider",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = ["*"]
  }

  # SSM: publish shared-services dev outputs after apply
  statement {
    sid    = "SSMDevPublish"
    effect = "Allow"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:GetParametersByPath",
      "ssm:ListTagsForResource",
      "ssm:PutParameter",
    ]
    resources = ["arn:aws:ssm:*:*:parameter/shared-services/*/dev/*"]
  }

  # STS: allow Terraform to read its own identity (used by ecr/iam.tf)
  statement {
    sid       = "STSCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_deployer_dev" {
  name        = "terraform-deployer-dev-policy"
  description = "Permissions for Terraform to deploy the dev shared-services environment"
  policy      = data.aws_iam_policy_document.terraform_deployer_dev.json

  tags = var.tags
}

resource "aws_iam_role" "terraform_deployer_dev" {
  name               = "terraform-deployer-dev"
  description        = "Assumed by Terraform to deploy the dev shared-services environment"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json

  # 1-hour session is enough for a typical terraform apply
  max_session_duration = 3600

  # Purpose and Environment are set per-role (not via var.tags) so the CLI can
  # filter on Purpose=terraform-deployer and display the correct environment label.
  tags = merge(var.tags, {
    Purpose     = "terraform-deployer"
    Environment = "dev"
  })
}

resource "aws_iam_role_policy_attachment" "terraform_deployer_dev" {
  role       = aws_iam_role.terraform_deployer_dev.name
  policy_arn = aws_iam_policy.terraform_deployer_dev.arn
}
