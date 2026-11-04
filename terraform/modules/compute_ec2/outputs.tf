output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.app.dns_name
}

output "alb_arn" {
  description = "Application Load Balancer ARN"
  value       = aws_lb.app.arn
}

output "alb_arn_suffix" {
  description = "Application Load Balancer ARN Suffix for CloudWatch alarms"
  value       = aws_lb.app.arn_suffix
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "Target Group ARN Suffix for CloudWatch alarms"
  value       = aws_lb_target_group.app.arn_suffix
}

output "asg_name" {
  description = "Auto Scaling Group Name"
  value       = aws_autoscaling_group.app.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.app.arn
}

output "ec2_role_arn" {
  description = "IAM Role ARN attached to EC2 instances"
  value       = aws_iam_role.ec2_role.arn
}

