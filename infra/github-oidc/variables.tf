variable "github_org" {
  type    = string
  default = "cve-community"
}

variable "github_repo" {
  type    = string
  default = "reference-archiver"
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
