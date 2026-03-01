aws_region = "ap-east-1"

github_org = "YOUR_GITHUB_ORG"

github_allowed_repos = [
  # Add your team repository names here, e.g. "team-payments-api"
]

repositories = {
  "dev/service-a" = {}
  "dev/service-b" = {
    tagged_image_count = 5
  }
}

tags = {
  Environment = "dev"
  Team        = "platform"
  ManagedBy   = "terraform"
}
