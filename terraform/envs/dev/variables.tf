variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name (must match bootstrap project for IAM scoping)"
  type        = string
  default     = "jignesh-devops"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "One NAT Gateway (cheaper) vs. one per AZ (HA)"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Route 53 public hosted zone, e.g. example.com. Empty = self-signed cert on the ALB DNS name."
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "Subdomain for the app; URL becomes https://<app_subdomain>.<domain_name>"
  type        = string
  default     = "app"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "deletion_protection" {
  description = "Deletion protection for RDS and the ALB. The Destroy workflow sets this to false before destroying."
  type        = bool
  default     = true
}

variable "db_multi_az" {
  description = "Enable RDS Multi-AZ standby (extra cost)"
  type        = bool
  default     = false
}
