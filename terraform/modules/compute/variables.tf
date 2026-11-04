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

variable "db_secret_arn" {
  description = "Secrets Manager secret ARN holding {username, password} for the DB (CAMPUSHUB_DATABASE_SECRET_ARN)"
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

variable "cognito_app_client_id" {
  description = "Cognito User Pool App Client ID (CAMPUSHUB_COGNITO_APP_CLIENT_ID)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used for CAMPUSHUB_COGNITO_REGION / CAMPUSHUB_S3_REGION)"
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

variable "tesseract_layer_zip" {
  description = "Path to the Tesseract layer zip built by modules/compute/tesseract_layer/build.sh. Empty = no layer: mess menus can't be read from files and the app says so."
  type        = string
  default     = ""
}

variable "community_events_memory_size" {
  description = "Memory for the community-events function (mess menu reading with OCR needs more CPU than 512 MB)"
  type        = number
  default     = 1024
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}
