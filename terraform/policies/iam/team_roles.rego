package iam.team_roles

import rego.v1

# ---------------------------------------------------------------------------
# Guard rails for team Terraform deployer roles.
#
# Applies only to roles named "terraform-deployer-team-*".
# The platform deployer role "terraform-deployer-dev" is intentionally exempt.
#
# Rules enforced:
#   1. permissions_boundary must be set (or unknown-after-apply on first create)
#   2. max_session_duration must not exceed 3600 seconds (1 hour)
#   3. Required tags: Purpose, Team, Environment, ManagedBy
#   4. tags.Purpose must equal "terraform-deployer"
# ---------------------------------------------------------------------------

# Collect all planned IAM role resources that are team deployer roles
team_roles contains resource if {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_role"
	startswith(resource.change.after.name, "terraform-deployer-team-")
}

# ---------------------------------------------------------------------------
# Rule 1: permissions_boundary must be set
# ---------------------------------------------------------------------------
deny contains msg if {
	role := team_roles[_]
	after := role.change.after

	# Null means the attribute is explicitly unset (not unknown-after-apply)
	after.permissions_boundary == null

	msg := sprintf(
		"Role '%s' must have permissions_boundary set. Add: permissions_boundary = aws_iam_policy.team_deployer_boundary.arn",
		[after.name],
	)
}

# ---------------------------------------------------------------------------
# Rule 2: max_session_duration must not exceed 3600 seconds
# ---------------------------------------------------------------------------
deny contains msg if {
	role := team_roles[_]
	after := role.change.after
	after.max_session_duration > 3600

	msg := sprintf(
		"Role '%s' has max_session_duration %d which exceeds the 3600-second limit.",
		[after.name, after.max_session_duration],
	)
}

# ---------------------------------------------------------------------------
# Rule 3: Required tags must all be present
# ---------------------------------------------------------------------------
required_tags := {"Purpose", "Team", "Environment", "ManagedBy"}

deny contains msg if {
	role := team_roles[_]
	after := role.change.after
	missing := required_tags - {tag | after.tags[tag]}
	count(missing) > 0

	msg := sprintf(
		"Role '%s' is missing required tags: %v",
		[after.name, missing],
	)
}

# ---------------------------------------------------------------------------
# Rule 4: tags.Purpose must equal "terraform-deployer"
# ---------------------------------------------------------------------------
deny contains msg if {
	role := team_roles[_]
	after := role.change.after
	after.tags.Purpose != "terraform-deployer"

	msg := sprintf(
		"Role '%s' has tags.Purpose = '%s'; it must be 'terraform-deployer'.",
		[after.name, after.tags.Purpose],
	)
}
