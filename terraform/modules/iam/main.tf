data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# Least privilege: only this secret, only this bucket
data "aws_iam_policy_document" "ec2_app" {
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [var.secret_arn]
  }

  statement {
    sid       = "ListAppBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.app_bucket_arn]
  }

  statement {
    sid       = "ReadWriteAppObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.app_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "ec2_app" {
  name   = "app-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_app.json
}

# SSM Session Manager instead of SSH keys / port 22
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}
