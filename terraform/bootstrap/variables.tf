variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name prefix (must match the main stack's project variable)"
  type        = string
  default     = "jignesh-devops"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the deploy role, as owner/name"
  type        = string
  default     = "jigneshpatel623-alt/aws-devops-task"
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this AWS account"
  type        = bool
  default     = true
}
