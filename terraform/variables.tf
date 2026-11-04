variable "aws_region" {
  description = "AWS deployment region (Mumbai: ap-south-1)"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
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

variable "enable_ec2_baseline" {
  description = "Provision an alternative EC2-based deployment (ALB + Auto Scaling Group, its own CloudFront distribution) alongside the serverless (Lambda + API Gateway) path, for benchmarking. Shares this stack's RDS, Cognito and media bucket. Additive only -- the serverless path is never modified or replaced. Not Free Tier eligible as a combination (two CloudFront distributions, an ALB, an EC2 instance, on top of everything else), though each piece individually is modest. Turn off again (terraform apply) once the comparison is done."
  type        = bool
  default     = false
}

variable "ec2_instance_type" {
  description = "Instance type for the EC2 baseline's Auto Scaling Group (t4g.micro is Free Tier eligible; ignored unless enable_ec2_baseline is true)"
  type        = string
  default     = "t4g.micro"
}

variable "ec2_baseline_asg_min_size" {
  description = "Minimum instances in the EC2 baseline's Auto Scaling Group"
  type        = number
  default     = 1
}

variable "ec2_baseline_asg_max_size" {
  description = "Maximum instances in the EC2 baseline's Auto Scaling Group"
  type        = number
  default     = 2
}

variable "ec2_baseline_asg_desired_capacity" {
  description = "Desired instances in the EC2 baseline's Auto Scaling Group"
  type        = number
  default     = 1
}

variable "ec2_baseline_origin_verify_header" {
  description = "Secret header value the EC2 baseline's CloudFront distribution sends to its ALB origin"
  type        = string
  default     = "CampusHub-Origin-Auth-Baseline"
}

variable "enable_rds_proxy" {
  description = "Set to true to provision RDS Proxy in front of the database, for load/perf testing. NOT Free Tier (~$0.015/vCPU-hour, 2 vCPU minimum, so ~$0.03/hour / ~$22/month if left running) — turn it off again (terraform apply) once testing is done. Switching it on or off only changes the Lambdas' CAMPUSHUB_DATABASE_URL env var, not their code, so no rebuild/redeploy is needed either way."
  type        = bool
  default     = false
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
  default     = []
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
  default     = 1000
}

variable "throttling_burst_limit" {
  description = "API Gateway burst capacity limit (PRD Section 8.4 Risk 1)"
  type        = number
  default     = 2000
}
