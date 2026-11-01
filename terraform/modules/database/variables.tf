variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "database_subnet_ids" {
  description = "List of private subnet IDs for RDS DB Subnet Group"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "Security Group ID for RDS Database tier"
  type        = string
}

variable "db_name" {
  description = "Database name for CampusHub"
  type        = string
  default     = "campushub"
}

variable "db_username" {
  description = "Master username for PostgreSQL database"
  type        = string
  default     = "campushub_admin"
}

variable "instance_class" {
  description = "RDS instance class (db.t4g.micro or db.t3.micro for AWS Free Tier)"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB (Free tier covers up to 20 GB)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage limit for autoscaling in GB (0 disables autoscaling for strict cost control)"
  type        = number
  default     = 0
}

variable "engine_version" {
  description = "PostgreSQL engine version (Use major version 16 to automatically resolve to the active minor version)"
  type        = string
  default     = "16"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment (Set false for AWS Free Tier; true for High-Availability production / benchmarks)"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion (Recommended true for non-prod / coursework)"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Days of automated backup retention (Set to 0 to disable if testing, up to 7 days for free tier)"
  type        = number
  default     = 1
}
