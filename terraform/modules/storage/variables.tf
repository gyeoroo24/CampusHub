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

variable "media_cors_origins" {
  description = "Origins allowed to upload to / read from the media bucket from a browser (the web app's)"
  type        = list(string)
  default     = []
}
