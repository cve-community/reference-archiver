terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = ">= 5.0" }
    archive = { source = "hashicorp/archive", version = ">= 2.0" }
  }

  # Same state the old iac/aws/archiver/dirlist stack used. Resource addresses
  # are kept identical so this config adopts the live resources in place:
  # no imports, no recreation. Never run the old iac stack against it again.
  backend "s3" {
    bucket         = "vulncorps-tofu-s3-backend"
    key            = "archiver-demo/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# Lambda@Edge and CloudFront certs must live in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
