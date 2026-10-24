variable "aws_region" {
  description = "AWS Region for Terraform backend resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "campushub"
}
