# Bootstrap stack: IAM roles that GitHub Actions in this repo assume via OIDC.
# Applied by hand by an account admin (CI can't create the roles it runs as).
#
#   cd infra/github-oidc && tofu init && tofu plan && tofu apply
#
# Then set repo variables AWS_ROLE_ARN, AWS_INFRA_PLAN_ROLE_ARN and
# AWS_INFRA_APPLY_ROLE_ARN from the outputs.

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket         = "vulncorps-tofu-s3-backend"
    key            = "reference-archiver/github-oidc.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

# Account-wide provider, created and owned by the iac/aws/oidc stack
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  # The repo uses GitHub's immutable OIDC subject (owner@id/repo@id), which
  # survives renames and can't be claimed by a recreated repo of the same name
  repo         = "${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}"
  bucket_arn   = "arn:aws:s3:::${var.archive_bucket}"
  state_bucket = "arn:aws:s3:::${var.state_bucket}"
  lock_table   = "arn:aws:dynamodb:us-west-2:${data.aws_caller_identity.current.account_id}:table/${var.lock_table}"
  role_prefix  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/reference-archiver-"
}

data "aws_iam_policy_document" "trust" {
  for_each = {
    # Scheduled + dispatched pipeline runs on main
    runtime = ["repo:${local.repo}:ref:refs/heads/main"]
    # tofu plan on PRs and on main
    infra_plan = ["repo:${local.repo}:pull_request", "repo:${local.repo}:ref:refs/heads/main"]
    # tofu apply only from the approval-gated `infra` environment
    infra_apply = ["repo:${local.repo}:environment:infra"]
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# Denies shared by every role: nothing in CI may delete archive data or
# state, or rewrite the roles it runs as.
data "aws_iam_policy_document" "data_protection" {
  statement {
    sid    = "DenyArchiveDeletion"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:PutBucketObjectLockConfiguration",
    ]
    resources = [local.bucket_arn, "${local.bucket_arn}/*", local.state_bucket, "${local.state_bucket}/*"]
  }
  statement {
    sid       = "DenySelfEscalation"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["${local.role_prefix}*", data.aws_iam_openid_connect_provider.github.arn]
  }
}

# --- runtime: archive pipeline (crawl, archive, rearchive, site) ---------
data "aws_iam_policy_document" "runtime" {
  source_policy_documents = [data.aws_iam_policy_document.data_protection.json]

  statement {
    sid       = "ListArchive"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["v2/*", "v2"]
    }
  }
  statement {
    sid       = "ReadWriteArchive"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${local.bucket_arn}/v2/*"]
  }
}

resource "aws_iam_role" "runtime" {
  name                 = "reference-archiver-runtime"
  assume_role_policy   = data.aws_iam_policy_document.trust["runtime"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "runtime" {
  name   = "archive-rw-no-delete"
  role   = aws_iam_role.runtime.id
  policy = data.aws_iam_policy_document.runtime.json
}

# --- infra_plan: read-only + state lock ---------------------------------
data "aws_iam_policy_document" "infra_plan" {
  source_policy_documents = [data.aws_iam_policy_document.data_protection.json]

  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.state_bucket, "${local.state_bucket}/*"]
  }
  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [local.lock_table]
  }
}

resource "aws_iam_role" "infra_plan" {
  name               = "reference-archiver-infra-plan"
  assume_role_policy = data.aws_iam_policy_document.trust["infra_plan"].json
}

resource "aws_iam_role_policy_attachment" "infra_plan_readonly" {
  role       = aws_iam_role.infra_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "infra_plan" {
  name   = "state-lock-and-data-protection"
  role   = aws_iam_role.infra_plan.id
  policy = data.aws_iam_policy_document.infra_plan.json
}

# --- infra_apply: admin minus data destruction --------------------------
resource "aws_iam_role" "infra_apply" {
  name               = "reference-archiver-infra-apply"
  assume_role_policy = data.aws_iam_policy_document.trust["infra_apply"].json
}

resource "aws_iam_role_policy_attachment" "infra_apply_admin" {
  role       = aws_iam_role.infra_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "infra_apply" {
  name   = "data-protection"
  role   = aws_iam_role.infra_apply.id
  policy = data.aws_iam_policy_document.data_protection.json
}

output "runtime_role_arn" {
  value = aws_iam_role.runtime.arn
}

output "infra_plan_role_arn" {
  value = aws_iam_role.infra_plan.arn
}

output "infra_apply_role_arn" {
  value = aws_iam_role.infra_apply.arn
}
