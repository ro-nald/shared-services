aws_region = "ap-east-1"

# Your GitHub organisation name (e.g. "acme-corp" or your username)
github_org = "YOUR_GITHUB_ORG"

# Repositories in the org that are allowed to push images to ECR.
# Use "*" to allow all repos, or list specific ones.
github_allowed_repos = [
  # "service-a",
  # "service-b",
]

# ECR repositories to create. Keys are repository names.
# tagged_image_count: max number of tagged images to keep (default 10)
# scan_on_push: enable vulnerability scanning on push (default true)
# image_tag_mutability: "IMMUTABLE" prevents tag overwrites (default)
repositories = {
  # "service-a" = {}
  # "service-b" = { tagged_image_count = 5 }
}

tags = {
  Team      = "platform"
  ManagedBy = "terraform"
}
