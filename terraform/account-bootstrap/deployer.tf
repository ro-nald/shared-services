# -----------------------------------------------------------------------------
# Deployer role for this workload account
#
# Policy: AdministratorAccess (AWS managed) — full service access within the
# account, bounded at runtime by the permission boundary below.
#
# Boundary: denies actions that should never be available to any deployer,
# regardless of what policies are attached — IAM user management, CloudTrail/
# Config modification, billing, and cross-account organization actions.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    sid     = "AllowCIPipeline"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = concat(
        ["arn:aws:iam::${var.shared_services_account_id}:role/ci-pipeline"],
        var.additional_trusted_arns,
      )
    }
  }
}

data "aws_iam_policy_document" "deployer_boundary" {
  statement {
    sid       = "AllowMostServices"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIAMUserManagement"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:UpdateUser",
      "iam:CreateLoginProfile",
      "iam:DeleteLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:UpdateAccessKey",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAuditInfrastructure"
    effect = "Deny"
    actions = [
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "config:DeleteConfigRule",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:StopConfigurationRecorder",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyBillingAndOrganizations"
    effect = "Deny"
    actions = [
      "aws-portal:*",
      "budgets:*",
      "cur:*",
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deployer_boundary" {
  name        = "terraform-deployer-boundary-${var.environment}"
  description = "Permission boundary for the ${var.environment} Terraform deployer role"
  policy      = data.aws_iam_policy_document.deployer_boundary.json
  tags        = var.tags
}

resource "aws_iam_role" "deployer" {
  name                 = "terraform-deployer-${var.environment}"
  description          = "Assumed by ci-pipeline (shared-services) to deploy the ${var.environment} environment"
  assume_role_policy   = data.aws_iam_policy_document.deployer_trust.json
  permissions_boundary = aws_iam_policy.deployer_boundary.arn
  max_session_duration = 3600

  tags = merge(var.tags, {
    Purpose     = "terraform-deployer"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "deployer_admin" {
  role       = aws_iam_role.deployer.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
