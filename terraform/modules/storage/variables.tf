variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "campushub"
}

variable "enable_cloudfront" {
  description = "Whether CloudFront CDN is enabled"
  type        = bool
  default     = false
}
