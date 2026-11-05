variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "app_subnet_ids" {
  description = "List of private subnet IDs for the ElastiCache subnet group (co-located with the app tier)"
  type        = list(string)
}

variable "redis_security_group_id" {
  description = "Security Group ID for ElastiCache Redis (ingress restricted to the app tier)"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node type (cache.t3.micro is AWS Free Tier eligible: 750 hrs/month for 12 months)"
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "num_cache_clusters" {
  description = "Number of cache nodes. 1 = single node (cheapest). >1 adds read replicas with automatic failover for benchmarking under load."
  type        = number
  default     = 1
}
