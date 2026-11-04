output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets for ALB"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "List of IDs of subnets for EC2 App tier"
  value       = aws_subnet.app[*].id
}

output "lambda_subnet_ids" {
  description = "List of IDs of private subnets for Lambda functions"
  value       = aws_subnet.app[*].id
}

output "database_subnet_ids" {
  description = "List of IDs of private subnets for RDS"
  value       = aws_subnet.database[*].id
}

output "alb_security_group_id" {
  description = "Security Group ID for Application Load Balancer"
  value       = aws_security_group.alb_sg.id
}

output "app_security_group_id" {
  description = "Security Group ID for Application tier"
  value       = aws_security_group.app_sg.id
}

output "db_security_group_id" {
  description = "Security Group ID for RDS Database tier"
  value       = aws_security_group.db_sg.id
}

output "s3_endpoint_id" {
  description = "The ID of the S3 VPC Gateway Endpoint"
  value       = aws_vpc_endpoint.s3.id
}
