locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"

  # Build the list of "sub" claim patterns that GitHub sends.
  # Pattern: repo:<org>/<repo>:*
  github_sub_conditions = [
    for repo in var.github_allowed_repos :
    "repo:${var.github_org}/${repo}:*"
  ]
}

# ---------------------------------------------------------------------------
# GitHub OIDC Identity Provider
# (skip with create_github_oidc_provider = false if it already exists)
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url = local.github_oidc_url

  client_id_list = ["sts.amazonaws.com"]

  # AWS verifies GitHub's TLS cert automatically; thumbprint is still required
  # by the API. GitHub's current intermediate CA thumbprint:
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM Role — assumed by GitHub Actions via OIDC
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_trust" {
  statement {
    sid     = "GitHubOIDCAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      identifiers = [
        var.create_github_oidc_provider
        ? aws_iam_openid_connect_provider.github[0].arn
        : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_sub_conditions
    }
  }
}

resource "aws_iam_role" "github_ecr_push" {
  name               = "github-ecr-push"
  description        = "Assumed by GitHub Actions to push images to ECR"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM Policy — ECR push permissions (scoped to repos in this deployment)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecr_push" {
  # Login to ECR (not resource-scoped)
  statement {
    sid    = "ECRAuthToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  # Push operations — scoped to only the repos managed here
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      # Needed for pull-before-push / cache checks
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      for repo in aws_ecr_repository.this :
      repo.arn
    ]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "github-ecr-push-policy"
  description = "Allows GitHub Actions to push images to shared-services ECR"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_ecr_push.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
