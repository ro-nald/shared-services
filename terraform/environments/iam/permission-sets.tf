# -----------------------------------------------------------------------------
# Platform-owned permission set building blocks
#
# Teams compose their deployer role policy from these data sources only.
# DO NOT add arbitrary IAM actions here without platform team review.
# To request a new permission set, open a PR targeting this file — it requires
# platform team approval only (see .github/CODEOWNERS).
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ECR — full management of repositories, lifecycle policies, and images
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_ecr_manage" {
  statement {
    sid       = "PSetECRFull"
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# S3 — bucket and object management
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_s3_manage" {
  statement {
    sid       = "PSetS3Full"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# EC2 — instance lifecycle, AMIs, security groups, key pairs
# (VPC networking is a separate permission set below)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_ec2_manage" {
  statement {
    sid    = "PSetEC2Manage"
    effect = "Allow"
    actions = [
      "ec2:AllocateAddress",
      "ec2:AssociateAddress",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateImage",
      "ec2:CreateKeyPair",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeAddresses",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "ec2:DisassociateAddress",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:ReleaseAddress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# VPC — network resource management
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_vpc_manage" {
  statement {
    sid    = "PSetVPCManage"
    effect = "Allow"
    actions = [
      "ec2:AssociateDhcpOptions",
      "ec2:AssociateRouteTable",
      "ec2:AssociateSubnetCidrBlock",
      "ec2:AssociateVpcCidrBlock",
      "ec2:AttachInternetGateway",
      "ec2:CreateDhcpOptions",
      "ec2:CreateInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:CreateNetworkAcl",
      "ec2:CreateNetworkAclEntry",
      "ec2:CreateRoute",
      "ec2:CreateRouteTable",
      "ec2:CreateSubnet",
      "ec2:CreateTags",
      "ec2:CreateVpc",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteDhcpOptions",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteNatGateway",
      "ec2:DeleteNetworkAcl",
      "ec2:DeleteNetworkAclEntry",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSubnet",
      "ec2:DeleteVpc",
      "ec2:DeleteVpcEndpoints",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNatGateways",
      "ec2:DescribeNetworkAcls",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcs",
      "ec2:DetachInternetGateway",
      "ec2:DisassociateRouteTable",
      "ec2:DisassociateSubnetCidrBlock",
      "ec2:DisassociateVpcCidrBlock",
      "ec2:ModifySubnetAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:ReplaceNetworkAclAssociation",
      "ec2:ReplaceNetworkAclEntry",
      "ec2:ReplaceRoute",
      "ec2:ReplaceRouteTableAssociation",
    ]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# IAM service roles — create/manage roles and policies for team-owned services
# (does NOT include user management or account-level IAM settings)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_iam_service_roles" {
  statement {
    sid    = "PSetIAMServiceRoles"
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
}

# ---------------------------------------------------------------------------
# STS caller identity — needed by most Terraform deployments to read the
# current account ID (e.g. to construct ARNs)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_sts_caller_identity" {
  statement {
    sid       = "PSetSTSCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# S3 team state — scoped read/write access to the team's own Terraform state
# prefix in the shared-services S3 bucket. Use this instead of pset_s3_manage
# for Terraform state access. Teams that also need to manage application S3
# buckets should open a PR to add a separate permission set.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_s3_team_state" {
  statement {
    sid     = "PSetS3TeamStateObjects"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.core.outputs.state_bucket_name}/teams/*",
    ]
  }

  statement {
    sid       = "PSetS3TeamStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::${data.terraform_remote_state.core.outputs.state_bucket_name}"]
  }
}

# ---------------------------------------------------------------------------
# SSM shared read — read-only access to shared-services SSM outputs published
# under the platform namespace. Grants access to the full namespace path;
# each team role file can further scope to specific sub-paths if needed.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pset_ssm_shared_read" {
  statement {
    sid    = "PSetSSMSharedRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/shared-services/${data.terraform_remote_state.core.outputs.ssm_namespace_id}/*",
    ]
  }
}
