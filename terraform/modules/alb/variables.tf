variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "logs_bucket" {
  description = "S3 bucket for ALB access logs"
  type        = string
}

variable "logs_prefix" {
  type    = string
  default = "alb"
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "create_dns_record" {
  description = "Create the Route 53 alias record for fqdn"
  type        = bool
  default     = true
}

variable "zone_id" {
  description = "Route 53 hosted zone ID for the app record (null when create_dns_record = false)"
  type        = string
  default     = null
}

variable "fqdn" {
  description = "Application hostname, e.g. app.example.com"
  type        = string
}
