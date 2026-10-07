variable "name_prefix" {
  description = "Name prefix for buckets"
  type        = string
}

variable "account_id" {
  description = "AWS account ID (makes bucket names globally unique)"
  type        = string
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete non-empty buckets"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Days to keep ALB access logs"
  type        = number
  default     = 30
}
