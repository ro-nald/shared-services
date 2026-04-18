# -----------------------------------------------------------------------------
# CI pipeline IAM role
#
# Assumed by GitHub Actions via OIDC to apply environments/iam/ and
# environments/dev/. This is NOT a human deployer role — it has no AWS
# principal trust. Human Terraform use is via terraform-deployer-dev
# (created in environments/iam/).
#
# Trust is scoped to the shared-services repository. Apply jobs further
# constrain the OIDC sub claim to ref:refs/heads/main in the workflow.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_pipeline_trust" {
  statement {
    sid     = "GitHubOIDCAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

data "aws_iam_policy_document" "ci_pipeline" {
  # -------------------------------------------------------------------------
  # IAM — manage deployer roles, policies, and permission boundary (iam/)
  # -------------------------------------------------------------------------
  statement {
    sid    = "IAMDeployerRoles"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = ["*"]
  }

  # -------------------------------------------------------------------------
  # IAM — manage OIDC provider and push role (dev/)
  # -------------------------------------------------------------------------
  statement {
    sid    = "IAMOIDCProvider"
    effect = "Allow"
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["*"]
  }

  # -------------------------------------------------------------------------
  # ECR — manage repositories and lifecycle policies (dev/)
  # -------------------------------------------------------------------------
  statement {
    sid       = "ECRFull"
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["*"]
  }

  # -------------------------------------------------------------------------
  # S3 — read/write Terraform state and native lockfiles
  # -------------------------------------------------------------------------
  statement {
    sid    = "TerraformStateReadList"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }

  statement {
    sid    = "TerraformStateWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]
  }

  # -------------------------------------------------------------------------
  # SSM — publish shared-services outputs after each apply (iam/ and dev/)
  # -------------------------------------------------------------------------
  statement {
    sid    = "SSMSharedServicesWrite"
    effect = "Allow"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:GetParametersByPath",
      "ssm:ListTagsForResource",
      "ssm:PutParameter",
    ]
    resources = ["arn:aws:ssm:*:*:parameter/shared-services/*"]
  }

  # -------------------------------------------------------------------------
  # STS — read caller identity (required by all environments)
  # -------------------------------------------------------------------------
  statement {
    sid       = "STSCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_pipeline" {
  name        = "ci-pipeline-policy"
  description = "Permissions for GitHub Actions to apply environments/iam/ and environments/dev/"
  policy      = data.aws_iam_policy_document.ci_pipeline.json

  tags = var.tags
}

resource "aws_iam_role" "ci_pipeline" {
  name               = "ci-pipeline"
  description        = "Assumed by GitHub Actions via OIDC to apply Terraform environments"
  assume_role_policy = data.aws_iam_policy_document.ci_pipeline_trust.json

  max_session_duration = 3600

  tags = merge(var.tags, {
    Purpose = "ci-pipeline"
  })
}

resource "aws_iam_role_policy_attachment" "ci_pipeline" {
  role       = aws_iam_role.ci_pipeline.name
  policy_arn = aws_iam_policy.ci_pipeline.arn
}
