variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to use"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "At least 2 AZs are required (ALB and RDS subnet groups need 2)."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT Gateway (cheaper); false = one NAT per AZ (highly available)"
  type        = bool
  default     = true
}
