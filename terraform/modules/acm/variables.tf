variable "domain_name" {
  description = "Route 53 public hosted zone name, e.g. example.com. Empty = self-signed mode."
  type        = string
  default     = ""
}

variable "fqdn" {
  description = "Hostname for the certificate, e.g. app.example.com (or the ALB DNS name in self-signed mode)"
  type        = string
}
