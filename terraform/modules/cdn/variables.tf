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

variable "frontend_bucket_id" {
  description = "Frontend S3 bucket ID"
  type        = string
}

variable "frontend_bucket_arn" {
  description = "Frontend S3 bucket ARN"
  type        = string
}

variable "frontend_bucket_regional_domain_name" {
  description = "Frontend S3 bucket regional domain name"
  type        = string
}

variable "api_endpoint" {
  description = "API Gateway endpoint URL (e.g., https://xyz.execute-api.ap-south-1.amazonaws.com)"
  type        = string
}

variable "web_acl_arn" {
  description = "Optional AWS WAF WebACL ARN (Empty string by default for Free Tier to avoid $5/mo fee)"
  type        = string
  default     = ""
}

variable "price_class" {
  description = "CloudFront Price Class (PriceClass_200 covers India edge locations and is within free tier 1TB limit)"
  type        = string
  default     = "PriceClass_200"
}

variable "origin_protocol_policy" {
  description = "Origin protocol policy for backend API origin (http-only for ALB, https-only for API Gateway)"
  type        = string
  default     = "http-only"
}

variable "origin_verify_header" {
  description = "Optional secret header value to send to backend origin"
  type        = string
  default     = "CampusHub-Origin-Auth-Baseline"
}
