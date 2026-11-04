output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "lambda_subnet_ids" {
  description = "List of IDs of private subnets for Lambda functions"
  value       = aws_subnet.lambda[*].id
}

output "database_subnet_ids" {
  description = "List of IDs of private subnets for RDS"
  value       = aws_subnet.database[*].id
}

output "app_security_group_id" {
  description = "Security Group ID for Lambda Application tier"
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

output "ec2_baseline_subnet_ids" {
  description = "Subnet IDs hosting the EC2 baseline's ALB and Auto Scaling Group (empty unless enable_ec2_baseline)"
  value       = aws_subnet.ec2_baseline[*].id
}

output "alb_security_group_id" {
  description = "Security Group ID for the EC2 baseline's ALB (empty unless enable_ec2_baseline)"
  value       = var.enable_ec2_baseline ? aws_security_group.alb_sg[0].id : ""
}

output "ec2_app_security_group_id" {
  description = "Security Group ID for the EC2 baseline's app tier (empty unless enable_ec2_baseline)"
  value       = var.enable_ec2_baseline ? aws_security_group.ec2_app_sg[0].id : ""
}
