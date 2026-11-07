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

variable "enable_lambda_endpoint" {
  description = "Interface endpoint so Lambdas in the VPC can invoke other Lambdas (the Web Push sender)"
  type        = bool
  default     = false
}
