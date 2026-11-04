variable "environment" {
  description = "Environment name"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the EC2 baseline's ALB (the origin this distribution fronts)"
  type        = string
}

variable "origin_verify_header" {
  description = "Custom header value CloudFront sends to the ALB origin"
  type        = string
}
