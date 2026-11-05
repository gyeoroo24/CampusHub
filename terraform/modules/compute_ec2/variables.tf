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

variable "asg_target_cpu_utilization" {
  description = "Target-tracking scaling policy: average ASG CPU% the scaling policy tries to hold. Kept well under 100 so it scales out before a t4g.micro's burstable CPU credits run out under sustained load."
  type        = number
  default     = 50
}

variable "db_pool_max_size" {
  description = "Max asyncpg pool connections each EC2 instance opens to RDS, written into the app's .env as CAMPUSHUB_DB_POOL_MAX_SIZE. Must satisfy (this * asg_max_size) <= the RDS instance class's max_connections, with headroom for the data_tools Lambda and manual psql sessions -- db.t4g.micro caps out around ~110 connections."
  type        = number
  default     = 10
}

variable "tesseract_layer_zip" {
  description = "Path to tesseract-layer.zip (from modules/compute/tesseract_layer/build.sh). Empty = no OCR on the instances."
  type        = string
  default     = ""
}

variable "ml_models_zip" {
  description = "Path to a zip of backend/models (from scripts/fetch_match_models.py --suggest-only): the category suggestion and course-feedback sentiment ONNX models. Empty = those features stay unavailable."
  type        = string
  default     = ""
}

variable "redis_enabled" {
  description = "Whether ElastiCache Redis is provisioned; gates whether user_data writes CAMPUSHUB_REDIS_* into the app's .env"
  type        = bool
  default     = false
}

variable "redis_host" {
  description = "ElastiCache Redis primary endpoint hostname"
  type        = string
  default     = ""
}

variable "redis_port" {
  description = "ElastiCache Redis port"
  type        = number
  default     = 6379
}

variable "redis_auth_secret_arn" {
  description = "Secrets Manager secret ARN holding the Redis AUTH token"
  type        = string
  default     = ""
}

