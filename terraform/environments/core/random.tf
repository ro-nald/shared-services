# -----------------------------------------------------------------------------
# SSM namespace GUID
#
# Generates a stable 6-character hex identifier used as the SSM path namespace
# for all shared-services parameters. Generated once on first apply and never
# changes. Distributed to teams via the SSM_NAMESPACE GitHub Actions variable.
# -----------------------------------------------------------------------------

resource "random_id" "ssm_namespace" {
  byte_length = 3 # 3 bytes → 6 lowercase hex characters
}
