output "certificate_arn" {
  description = "Validated (or imported) certificate ARN"
  value       = one(concat(aws_acm_certificate_validation.this[*].certificate_arn, aws_acm_certificate.imported[*].arn))
}

output "zone_id" {
  description = "Route 53 zone ID, null in self-signed mode"
  value       = one(data.aws_route53_zone.this[*].zone_id)
}

output "self_signed" {
  value = var.domain_name == ""
}
