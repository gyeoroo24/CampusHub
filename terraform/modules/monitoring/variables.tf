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

variable "enable_alb_alarm" {
  description = "Set to true to provision CloudWatch alarm for Application Load Balancer"
  type        = bool
  default     = false
}

variable "enable_api_gateway_alarm" {
  description = "Set to true to provision CloudWatch alarm for API Gateway"
  type        = bool
  default     = false
}

variable "api_id" {
  description = "API Gateway HTTP API ID (Optional in baseline)"
  type        = string
  default     = ""
}

variable "db_instance_id" {
  description = "RDS DB instance ID"
  type        = string
}

variable "lambda_function_names" {
  description = "Map of Lambda function names (Empty in baseline)"
  type        = map(string)
  default     = {}
}

variable "alb_arn_suffix" {
  description = "Application Load Balancer ARN Suffix for alarms"
  type        = string
  default     = ""
}

variable "asg_name" {
  description = "Auto Scaling Group name for alarms"
  type        = string
  default     = ""
}
