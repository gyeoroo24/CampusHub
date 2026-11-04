output "hosted_ui_domain_prefix" {
  description = "Prefix of the Hosted UI domain (the full host is <prefix>.auth.<region>.amazoncognito.com)"
  value       = aws_cognito_user_pool_domain.hosted_ui.domain
}

output "user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.pool.id
}

output "user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.pool.arn
}

output "user_pool_endpoint" {
  description = "The endpoint name of the user pool"
  value       = aws_cognito_user_pool.pool.endpoint
}

output "user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.client.id
}
