# This is where Day 1-2 infra will grow (VPC, ALB, ECS, RDS...).
# Start tiny: one bucket, just to prove the pipeline works.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key          = "infra/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true # native S3 locking (Terraform 1.10+), no DynamoDB needed
    # bucket is passed in by the pipeline: -backend-config="bucket=..."
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Project   = "fan-platform"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_s3_bucket" "assets" {
  bucket_prefix = "fan-platform-assets-"
  force_destroy = true # practice only, so destroy works with objects inside

  tags = {
    Purpose = "pipeline-test"
        }
}
