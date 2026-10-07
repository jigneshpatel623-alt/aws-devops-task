# One-time bootstrap, applied locally with admin credentials:
#   - S3 bucket for Terraform remote state (locking via S3 lockfile)
#   - GitHub Actions OIDC provider + deploy role (no long-lived AWS keys)

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project}-tfstate-${local.account_id}"
}

# ---------------------------------------------------------------------------
# Terraform state bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_sub_prefixes = compact([
    "repo:${var.github_repo}",
    var.github_immutable_sub_prefix,
  ])

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only this repository: main branch, pull requests, and the production environment.
    # Accepts both the classic subject (repo:owner/name:...) and GitHub's immutable
    # subject (repo:owner@<owner_id>/name@<repo_id>:...).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for prefix in local.github_sub_prefixes : [
          "${prefix}:ref:refs/heads/main",
          "${prefix}:pull_request",
          "${prefix}:environment:production",
        ]
      ])
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "github-actions-terraform-${var.project}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

# Broad service access for Terraform to create the stack (no IAM user/account admin)
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# IAM permissions scoped to project-prefixed roles / instance profiles only
data "aws_iam_policy_document" "scoped_iam" {
  statement {
    sid = "ManageProjectRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.project}-*"]
  }

  statement {
    sid = "ManageProjectInstanceProfiles"
    actions = [
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${local.account_id}:instance-profile/${var.project}-*"]
  }

  statement {
    sid       = "ReadOnlyIam"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicies"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "scoped_iam" {
  name   = "scoped-iam"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.scoped_iam.json
}
