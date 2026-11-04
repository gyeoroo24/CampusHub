variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "campushub"
}

variable "cognito_domain_prefix" {
  description = "Prefix of the Hosted UI domain (<prefix>.auth.<region>.amazoncognito.com). Must be unique across AWS. Empty = <project>-<environment>-<account id>."
  type        = string
  default     = ""
}

variable "additional_callback_urls" {
  description = "Extra app addresses Cognito may redirect back to, e.g. the CloudFront URL of the web app. Set this after the first apply (the CloudFront URL is only known then), then apply again. The same list is used for logout URLs."
  type        = list(string)
  default     = []
}

