# Customer-managed KMS key for Secrets Manager, RDS and the app S3 bucket.
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "key" {
  # Account administrators manage the key; services use it through the
  # caller's IAM permissions (e.g. the EC2 role's kms:Decrypt grant).
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "${var.name_prefix} encryption key (Secrets Manager, RDS, S3)"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key.json

  tags = { Name = "${var.name_prefix}-kms" }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.this.key_id
}
