# -----------------------------------------------------------------------------
# GitHub OIDC identity provider
#
# One per AWS account. If this provider already exists (created outside
# Terraform), import it before applying:
#
#   OIDC_ARN=$(aws iam list-open-id-connect-providers \
#     --query "OpenIDConnectProviderList[?contains(Arn,'token.actions.githubusercontent.com')].Arn" \
#     --output text)
#   terraform import aws_iam_openid_connect_provider.github "$OIDC_ARN"
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's current intermediate CA thumbprint (SHA-1).
  # AWS verifies the TLS cert at runtime; this value is still required by the API.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.tags, {
    Purpose = "github-oidc"
  })
}
