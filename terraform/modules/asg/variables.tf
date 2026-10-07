variable "name_prefix" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "user_data" {
  description = "Rendered (not base64) user data script"
  type        = string
}

variable "security_group_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "target_group_arns" {
  type = list(string)
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "cpu_target" {
  description = "Target average CPU % for scaling"
  type        = number
  default     = 60
}
