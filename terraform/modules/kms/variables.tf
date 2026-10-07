variable "name_prefix" {
  type = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion takes effect (7-30)"
  type        = number
  default     = 7
}
