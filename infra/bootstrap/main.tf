# Bootstrap stack: the tofu state bucket and lock table every other stack in
# this repo uses. Applied by hand by an account admin. Adopted on 2026-10-26
# from VulnCorps/iac/aws/bootstrap (whose state was never in the bucket).
#
#   cd infra/bootstrap && tofu init && tofu plan && tofu apply
#
# It stores its own state in the bucket it manages; that's fine because the
# bucket is prevent_destroy and never recreated.

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket         = "vulncorps-tofu-s3-backend"
    key            = "reference-archiver/bootstrap.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"
}

locals {
  state_bucket = "vulncorps-tofu-s3-backend"
  lock_table   = "terraform-locks"
}

import {
  to = aws_s3_bucket.tf_state
  id = local.state_bucket
}

import {
  to = aws_s3_bucket_versioning.tf_state
  id = local.state_bucket
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.tf_state
  id = local.state_bucket
}

import {
  to = aws_s3_bucket_public_access_block.tf_state
  id = local.state_bucket
}

import {
  to = aws_dynamodb_table.tf_locks
  id = local.lock_table
}

resource "aws_s3_bucket" "tf_state" {
  bucket = local.state_bucket
  tags   = { Name = "terraform-state" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_locks" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  tags         = { Name = "terraform-locks" }

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}
