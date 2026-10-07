output "app_bucket_id" {
  value = aws_s3_bucket.this["app"].id
}

output "app_bucket_arn" {
  value = aws_s3_bucket.this["app"].arn
}

# Referenced through the policy so the ALB is only created after log delivery is allowed
output "logs_bucket_id" {
  value = aws_s3_bucket_policy.logs.bucket
}

output "logs_prefix" {
  value = "alb"
}
