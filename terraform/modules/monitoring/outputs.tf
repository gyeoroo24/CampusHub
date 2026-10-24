output "alerts_sns_topic_arn" {
  description = "The ARN of the SNS topic for alarms and budget alerts"
  value       = aws_sns_topic.alerts.arn
}

output "budget_name" {
  description = "The name of the AWS Free Tier budget"
  value       = aws_budgets_budget.free_tier_budget.name
}
