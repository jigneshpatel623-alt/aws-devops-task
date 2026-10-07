variable "name_prefix" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_host" {
  description = "RDS endpoint address"
  type        = string
}

variable "db_port" {
  type    = number
  default = 3306
}

variable "recovery_window_in_days" {
  description = "0 = delete immediately on destroy (handy for demo environments)"
  type        = number
  default     = 0
}
