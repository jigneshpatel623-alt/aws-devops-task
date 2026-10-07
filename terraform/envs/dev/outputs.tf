output "app_url" {
  description = "HTTPS application URL"
  value       = "https://${local.app_fqdn}"
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "asg_name" {
  value = module.asg.asg_name
}

output "rds_endpoint" {
  value = module.rds.address
}

output "db_secret_arn" {
  value = module.secrets.secret_arn
}

output "app_bucket" {
  value = module.s3.app_bucket_id
}

output "alb_logs_bucket" {
  value = module.s3.logs_bucket_id
}

output "nat_gateway_ips" {
  value = module.vpc.nat_gateway_public_ips
}
