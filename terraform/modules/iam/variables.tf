variable "name_prefix" {
  type = string
}

variable "secret_arn" {
  description = "ARN of the DB credentials secret"
  type        = string
}

variable "app_bucket_arn" {
  description = "ARN of the application S3 bucket"
  type        = string
}
