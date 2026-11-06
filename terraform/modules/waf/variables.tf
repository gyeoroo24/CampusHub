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

variable "rate_limit" {
  description = "Rate limit per 5-minute period per IP"
  type        = number
  default     = 2000
}
