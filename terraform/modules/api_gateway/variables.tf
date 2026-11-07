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

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
}

variable "cognito_user_pool_endpoint" {
  description = "Cognito User Pool Endpoint"
  type        = string
}

variable "lambda_invoke_arns" {
  description = "Map of Lambda invocation ARNs from compute module"
  type        = map(string)
}

variable "lambda_function_names" {
  description = "Map of Lambda function names from compute module"
  type        = map(string)
}

variable "throttling_rate_limit" {
  description = "Steady-state request rate limit per second (PRD Risk 1 mitigation: 50)"
  type        = number
  default     = 50
}

variable "throttling_burst_limit" {
  description = "Burst request limit (PRD Risk 1 mitigation: 100)"
  type        = number
  default     = 100
}

variable "cors_allow_origins" {
  description = "Origins allowed to call the API from a browser on another origin (the web app's)"
  type        = list(string)
  default     = []
}
