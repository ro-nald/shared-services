aws_region = "ap-east-1"

# Leave empty to allow any IAM entity in the account (recommended for dev).
# Add specific ARNs to restrict which principals can assume the deployer roles.
trusted_principal_arns = []

tags = {
  Team      = "platform"
  ManagedBy = "terraform"
}
