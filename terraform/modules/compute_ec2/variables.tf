variable "environment" {
  description = "Environment name (dev, baseline, prod)"
  type        = string
  default     = "baseline"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "campushub"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for Application Load Balancer"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Subnets for EC2 Auto Scaling Group"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group for EC2 instances"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group for Application Load Balancer"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (t4g.micro for Graviton ARM64 or t3.micro for x86_64, both Free Tier eligible)"
  type        = string
  default     = "t4g.micro"
}

variable "db_host" {
  description = "RDS PostgreSQL host endpoint"
  type        = string
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "campushub"
}

variable "db_user" {
  description = "RDS database user"
  type        = string
  default     = "campushub_admin"
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN containing database credentials"
  type        = string
}

variable "media_bucket_id" {
  description = "S3 bucket ID for uploads and media"
  type        = string
}

variable "media_bucket_arn" {
  description = "S3 bucket ARN for uploads and media"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "cognito_app_client_id" {
  description = "Cognito App Client ID"
  type        = string
}

variable "origin_verify_header" {
  description = "Custom secret header value sent by CloudFront to verify traffic authenticity"
  type        = string
  default     = "CampusHub-Origin-Auth-Baseline"
}

variable "asg_min_size" {
  description = "Minimum instances in ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum instances in ASG"
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Desired instances in ASG"
  type        = number
  default     = 1
}
