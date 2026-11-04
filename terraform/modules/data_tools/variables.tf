variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "campushub"
}

variable "lambda_runtime" {
  type    = string
  default = "python3.11"
}

variable "lambda_subnet_ids" {
  description = "Private subnets for the data-tools function (same as the API functions, so it can reach RDS)"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group that RDS accepts connections from (the API functions' group)"
  type        = string
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "media_bucket_id" {
  type = string
}

variable "media_bucket_arn" {
  type = string
}
