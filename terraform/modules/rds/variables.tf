variable "name_prefix" {
  type = string
}

variable "subnet_ids" {
  description = "Private DB subnet IDs (at least 2 AZs)"
  type        = list(string)
}

variable "security_group_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "engine_version" {
  type    = string
  default = "8.0"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling (GiB)"
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Standby replica in a second AZ (recommended for production)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for storage encryption"
  type        = string
}

variable "deletion_protection" {
  description = "Block deletion of the DB instance (the Destroy workflow disables it first)"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}
