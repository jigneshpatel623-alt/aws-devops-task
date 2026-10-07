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

variable "github_immutable_sub_prefix" {
  description = <<-EOT
    GitHub's immutable OIDC subject prefix for the repo, as returned by
    `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (sub_claim_prefix).
    Set to "" if the repo uses only the classic repo:owner/name subject.
  EOT
  type        = string
  default     = "repo:jigneshpatel623-alt@259783880/aws-devops-task@1409037056"
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this AWS account"
  type        = bool
  default     = true
}
