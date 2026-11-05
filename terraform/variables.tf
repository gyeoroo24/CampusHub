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

variable "enable_elasticache" {
  description = "Set to true to provision ElastiCache Redis in front of RDS for the EC2 app tier (Note: cache.t3.micro is Free Tier eligible for the first 750 hrs/month for 12 months, then billed)"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of Redis cache nodes (1 = single node; >1 adds read replicas with automatic failover)"
  type        = number
  default     = 1
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
  description = "Extra web-app addresses for Cognito redirects, e.g. [\"https://<cloudfront-domain>/\"]. Configured in terraform.tfvars."
  type        = list(string)
  default     = []
}

variable "tesseract_layer_zip" {
  description = "Path (relative to the terraform directory) to tesseract-layer.zip from modules/compute/tesseract_layer/build.sh. Empty = no OCR layer; mess menus can't be read from files."
  type        = string
  default     = ""
}

variable "ml_models_zip" {
  description = "Path (relative to the terraform directory) to a zip of backend/models from scripts/fetch_match_models.py --suggest-only. Empty = no category suggestion or course-feedback sentiment analysis."
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
  # Raised to 3 so asg_desired_capacity=3 is a real floor target-tracking won't scale below, not
  # just an initial value it can drift down from. This is a deliberate move off Free Tier: 3
  # t4g.micro running 24/7 is ~2190 instance-hours/month against the 750-hour combined Free Tier
  # budget, i.e. real ongoing cost -- accepted here in exchange for availability margin.
  description = "Minimum instances in EC2 Auto Scaling Group"
  type        = number
  default     = 3
}

variable "asg_max_size" {
  # Ceiling for scale-out -- extra instances beyond asg_desired_capacity only run (and only cost
  # instance-hours) while the target-tracking policy judges them needed, then scale back toward
  # asg_desired_capacity (not asg_min_size, which floors scale-IN too -- see its own comment).
  # Capped at 5 so that at ec2_db_pool_max_size=16 each, 5 * 16 = 80 connections stays safely under
  # db.t4g.micro's ~100-110 max_connections, leaving headroom for the data_tools Lambda and any
  # manual psql session.
  description = "Maximum instances in EC2 Auto Scaling Group"
  type        = number
  default     = 5
}

variable "asg_desired_capacity" {
  description = "Desired instances in EC2 Auto Scaling Group"
  type        = number
  default     = 3
}

variable "asg_target_cpu_utilization" {
  description = "Target-tracking scaling policy: average ASG CPU% it tries to hold."
  type        = number
  default     = 60
}

variable "asg_target_requests_per_instance" {
  description = "Target-tracking scaling policy: ALB requests per target per minute each instance should handle."
  type        = number
  default     = 200
}

variable "ec2_db_pool_max_size" {
  description = "Max asyncpg pool connections each EC2 instance opens to RDS (CAMPUSHUB_DB_POOL_MAX_SIZE). Must satisfy (this * asg_max_size) <= db.t4g.micro's ~100-110 max_connections, with headroom for the data_tools Lambda and any manual psql session -- see asg_max_size."
  type        = number
  default     = 16
}
