# Run ONCE from your laptop (terraform init && terraform apply).
# Creates: state bucket, GitHub OIDC provider, and two roles
#   - plan role  : read-only, usable only from pull requests
#   - apply role : can change infra, usable only from the main branch

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-northeast-2" # Seoul
}

variable "github_repo" {
  type        = string
  description = "Your repo as owner/name, e.g. yourname/fan-platform"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "me" {}

# ---------- Remote state bucket ----------
resource "aws_s3_bucket" "tfstate" {
  bucket = "tfstate-${data.aws_caller_identity.me.account_id}-${var.region}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- GitHub OIDC (no access keys stored in GitHub) ----------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Trust policy: only tokens from YOUR repo, and only from the given "sub" claim
data "aws_iam_policy_document" "trust" {
  for_each = {
    plan  = "repo:${var.github_repo}:pull_request"
    apply = "repo:${var.github_repo}:ref:refs/heads/main"
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "gha" {
  for_each             = data.aws_iam_policy_document.trust
  name                 = "github-actions-${each.key}"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
}

# Plan role: read everything + read/write state & lock file
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.gha["plan"].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "tfstate-access"
  role   = aws_iam_role.gha["plan"].id
  policy = data.aws_iam_policy_document.state_access.json
}

# Apply role: Admin is OK for a practice account.
# Interview topic: how would you scope this down? (permission boundaries,
# per-service policies, separate roles per stack)
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.gha["apply"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "state_bucket" { value = aws_s3_bucket.tfstate.bucket }
output "plan_role_arn" { value = aws_iam_role.gha["plan"].arn }
output "apply_role_arn" { value = aws_iam_role.gha["apply"].arn }
