variable "aws_region" {
  description = "AWS deployment region (Mumbai: ap-south-1)"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name (dev, baseline, staging, prod)"
  type        = string
  default     = "baseline"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "campushub"
}

# ==========================================
# Free Tier & Cost Optimization Flags
# ==========================================
variable "enable_cloudfront" {
  description = "Set to true to provision CloudFront CDN."
  type        = bool
  default     = true
}

variable "enable_waf" {
  description = "Set to true to provision AWS WAF (Note: AWS WAF charges ~$5/month + rule fees outside Free Tier. Default false ensures $0 cost)"
  type        = bool
  default     = false
}

variable "multi_az_db" {
  description = "Set to true for Multi-AZ PostgreSQL RDS (Note: Free Tier covers 750 hrs/month of Single-AZ only. Keep false for Free Tier)"
  type        = bool
  default     = true
}

variable "db_engine_version" {
  description = "PostgreSQL engine version (major version 16 automatically resolves to the latest active minor version in the region)"
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "RDS instance class (db.t4g.micro or db.t3.micro is AWS Free Tier eligible)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB (Free tier covers up to 20 GB gp2/gp3)"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial PostgreSQL database name"
  type        = string
  default     = "campushub"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "campushub_admin"
}

variable "alert_email" {
  description = "Email address for AWS Budgets cost alerts and CloudWatch alarms"
  type        = string
  default     = "dinkylakhani@iisc.ac.in"
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget limit in USD to enforce Free Tier adherence"
  type        = string
  default     = "50.0"
}

variable "cognito_domain_prefix" {
  description = "Prefix of the Cognito Hosted UI domain. Must be unique across AWS. Empty = campushub-<env>-<account id>. For an existing deployment, set it to the domain already in use so Terraform doesn't create a second one."
  type        = string
  default     = ""
}

variable "additional_callback_urls" {
  description = "Extra web-app addresses for Cognito redirects, e.g. [\"https://<cloudfront-domain>/\"]. Set after the first apply, then apply again."
  type        = list(string)
  default     = ["https://dohlbabjfehbe.cloudfront.net/"]
}

variable "tesseract_layer_zip" {
  description = "Path (relative to the terraform directory) to tesseract-layer.zip from modules/compute/tesseract_layer/build.sh. Empty = no OCR layer; mess menus can't be read from files."
  type        = string
  default     = ""
}

variable "ml_layer_zip" {
  description = "Path (relative to the terraform directory) to ml-layer.zip from modules/compute/ml_layer/build.sh. Empty = no ML layer; Buy & Sell and Lost & Found category suggestions are off."
  type        = string
  default     = ""
}

variable "community_events_memory_size" {
  description = "Memory (MB) for the community-events function, which reads mess menus"
  type        = number
  default     = 1024
}

variable "lambda_memory_size" {
  description = "Memory allocated to each Lambda function in MB"
  type        = number
  default     = 512
}

variable "throttling_rate_limit" {
  description = "API Gateway steady-state request rate limit (req/s) (PRD Section 8.4 Risk 1)"
  type        = number
  default     = 50
}

variable "throttling_burst_limit" {
  description = "API Gateway burst capacity limit (PRD Section 8.4 Risk 1)"
  type        = number
  default     = 100
}

# ==========================================
# Baseline EC2 Architecture Variables
# ==========================================
variable "ec2_instance_type" {
  description = "EC2 instance type for Baseline compute (t4g.micro for Graviton ARM64 or t3.micro for x86_64, both Free Tier eligible)"
  type        = string
  default     = "t4g.micro"
}

variable "origin_verify_header" {
  description = "Custom secret header value sent by CloudFront to verify traffic authenticity at origin"
  type        = string
  default     = "CampusHub-Origin-Auth-Baseline"
}

variable "asg_min_size" {
  description = "Minimum instances in EC2 Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum instances in EC2 Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Desired instances in EC2 Auto Scaling Group"
  type        = number
  default     = 1
}
