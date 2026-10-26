variable "github_org" {
  type    = string
  default = "cve-community"
}

variable "github_repo" {
  type    = string
  default = "reference-archiver"
}

# From `gh api repos/<org>/<repo>/actions/oidc/customization/sub`
variable "github_org_id" {
  type    = number
  default = 346011098
}

variable "github_repo_id" {
  type    = number
  default = 1434625726
}

variable "archive_bucket" {
  type    = string
  default = "archiver-demo-v1-public"
}

variable "state_bucket" {
  type    = string
  default = "vulncorps-tofu-s3-backend"
}

variable "lock_table" {
  type    = string
  default = "terraform-locks"
}
