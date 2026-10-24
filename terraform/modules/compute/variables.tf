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

variable "lambda_subnet_ids" {
  description = "Private subnet IDs across 3 AZs for Lambda functions"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security Group ID for Lambda functions"
  type        = string
}

variable "db_host" {
  description = "RDS PostgreSQL database host address"
  type        = string
}

variable "db_name" {
  description = "RDS database name"
  type        = string
}

variable "db_user" {
  description = "RDS master username"
  type        = string
}

variable "db_password_ssm_param" {
  description = "SSM Parameter Store name for RDS password"
  type        = string
}

variable "media_bucket_id" {
  description = "S3 bucket ID for user uploads & documents"
  type        = string
}

variable "media_bucket_arn" {
  description = "S3 bucket ARN for user uploads & documents"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "lambda_memory_size" {
  description = "Lambda memory allocation in MB (512 MB gives solid CPU balance for FastAPI/Mangum)"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda execution timeout in seconds"
  type        = number
  default     = 29
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}
