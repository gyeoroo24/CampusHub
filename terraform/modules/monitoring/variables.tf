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

variable "alert_email" {
  description = "Email address for AWS Budgets cost alerts and operational alarms"
  type        = string
  default     = "team-phoenix-alerts@example.com"
}

variable "monthly_budget_usd" {
  description = "Monthly budget limit in USD to ensure strict AWS Free Tier compliance"
  type        = string
  default     = "5.0"
}

variable "api_id" {
  description = "API Gateway HTTP API ID"
  type        = string
}

variable "db_instance_id" {
  description = "RDS DB instance ID"
  type        = string
}

variable "lambda_function_names" {
  description = "Map of Lambda function names"
  type        = map(string)
}

variable "enable_alb_alarm" {
  description = "Create the EC2 baseline's ALB 5XX alarm (only meaningful when enable_ec2_baseline is true)"
  type        = bool
  default     = false
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for the 5XX alarm's dimension (required when enable_alb_alarm is true)"
  type        = string
  default     = ""
}
