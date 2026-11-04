variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of Availability Zones in the region"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "lambda_subnet_cidrs" {
  description = "CIDR blocks for Lambda private subnets across 3 AZs matching diagram"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for RDS database subnets across 3 AZs"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "ap-south-1"
}

variable "enable_ec2_baseline" {
  description = "Provision the networking (subnets, IGW, security groups) the EC2 baseline deployment needs, alongside the Lambda path. See the root variable of the same name."
  type        = bool
  default     = false
}

variable "ec2_baseline_subnet_cidrs" {
  description = "CIDR blocks for the EC2 baseline's subnets (hosts both the ALB and the Auto Scaling Group) across 3 AZs. Distinct from lambda_subnet_cidrs/db_subnet_cidrs so nothing collides."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
}
