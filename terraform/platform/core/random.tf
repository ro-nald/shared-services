# -----------------------------------------------------------------------------
# SSM namespace GUID
#
# Generates a stable 6-character hex identifier used as the SSM path namespace
# for all shared-services parameters. Generated once on first apply and never
# changes. Read by iam/ and dev/ via data "terraform_remote_state" "core".
# -----------------------------------------------------------------------------

resource "random_id" "ssm_namespace" {
  byte_length = 3 # 3 bytes → 6 lowercase hex characters
}
