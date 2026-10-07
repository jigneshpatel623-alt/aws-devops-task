# Two modes:
#   domain_name set   -> public ACM certificate, DNS-validated in Route 53 (trusted by browsers)
#   domain_name = ""  -> self-signed certificate imported into ACM (HTTPS works, browser warns)

locals {
  use_dns = var.domain_name != ""
}

# --- Mode 1: Route 53 + DNS-validated ACM certificate -----------------------
data "aws_route53_zone" "this" {
  count        = local.use_dns ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  count             = local.use_dns ? 1 : 0
  domain_name       = var.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = var.fqdn }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in flatten(aws_acm_certificate.this[*].domain_validation_options) : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "this" {
  count                   = local.use_dns ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# --- Mode 2: self-signed certificate imported into ACM ----------------------
resource "tls_private_key" "self_signed" {
  count     = local.use_dns ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "this" {
  count           = local.use_dns ? 0 : 1
  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = var.fqdn
    organization = "DevOps Practical Task"
  }

  dns_names             = [var.fqdn]
  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_acm_certificate" "imported" {
  count            = local.use_dns ? 0 : 1
  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.this[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.fqdn}-self-signed" }
}
