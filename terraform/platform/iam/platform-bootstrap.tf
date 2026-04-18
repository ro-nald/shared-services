# -----------------------------------------------------------------------------
# Platform bootstrap role
#
# Assumed by a platform engineer when re-running apply-core after the initial
# bootstrap. Provides the minimum permissions required to create the S3 state
# bucket, GitHub OIDC provider, and ci-pipeline IAM role/policy that core
# manages.
#
# NOTE: This role cannot solve the chicken-and-egg for the very first bootstrap
# run — that still requires admin credentials. Once iam/ has been applied for
# the first time (by CI), this role is available for all subsequent apply-core
# re-runs.
#
# To use: add a named profile to ~/.aws/config pointing at this role's ARN
# (see README.md — Re-running apply-core), then run:
#   AWS_PROFILE=platform-bootstrap uv run scripts/bootstrap.py apply-core
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "platform_bootstrap" {
  # S3 — create and configure the Terraform state bucket, and read/write core state
  statement {
    sid    = "S3CoreStateBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutObject",
    ]
    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.core.outputs.state_bucket_name}",
      "arn:aws:s3:::${data.terraform_remote_state.core.outputs.state_bucket_name}/*",
    ]
  }

  # IAM — create the GitHub OIDC provider and ci-pipeline role/policy that core manages
  statement {
    sid    = "IAMCoreResources"
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

  # STS — read caller identity (required by Terraform to construct ARNs)
  statement {
    sid       = "STSCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "platform_bootstrap" {
  name        = "platform-bootstrap-policy"
  description = "Minimum permissions for a platform engineer to re-run apply-core"
  policy      = data.aws_iam_policy_document.platform_bootstrap.json

  tags = var.tags
}

resource "aws_iam_role" "platform_bootstrap" {
  name               = "platform-bootstrap"
  description        = "Assumed by a platform engineer to re-run the core bootstrap (apply-core)"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json

  max_session_duration = 3600

  tags = merge(var.tags, {
    Purpose = "platform-bootstrap"
  })
}

resource "aws_iam_role_policy_attachment" "platform_bootstrap" {
  role       = aws_iam_role.platform_bootstrap.name
  policy_arn = aws_iam_policy.platform_bootstrap.arn
}
