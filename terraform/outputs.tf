# ==========================================
# CampusHub Infrastructure Outputs
# ==========================================

output "app_url" {
  description = "The CloudFront URL to access the CampusHub Web Application (or API Gateway URL if CDN is disabled)"
  value       = var.enable_cloudfront ? "https://${module.cdn[0].cloudfront_domain_name}" : module.api_gateway.api_endpoint
}

output "frontend_url" {
  description = "Direct Web Application Frontend URL (CloudFront if enabled, else S3 Website Endpoint)"
  value       = var.enable_cloudfront ? "https://${module.cdn[0].cloudfront_domain_name}" : "http://${module.storage.frontend_website_endpoint}"
}

output "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name (if enabled)"
  value       = var.enable_cloudfront ? module.cdn[0].cloudfront_domain_name : null
}

output "api_endpoint" {
  description = "The Direct API Gateway HTTP API Endpoint URL"
  value       = module.api_gateway.api_endpoint
}

output "cognito_hosted_ui_domain" {
  description = "Hosted UI host the web app uses for sign-in (COGNITO_DOMAIN build define)"
  value       = "${module.auth.hosted_ui_domain_prefix}.auth.${var.aws_region}.amazoncognito.com"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation after a frontend release)"
  value       = var.enable_cloudfront ? module.cdn[0].cloudfront_distribution_id : null
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for Authentication"
  value       = module.auth.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito User Pool App Client ID"
  value       = module.auth.user_pool_client_id
}

output "frontend_s3_bucket" {
  description = "S3 Bucket for Flutter Web Static Content"
  value       = module.storage.frontend_bucket_id
}

output "media_s3_bucket" {
  description = "S3 Bucket for Media, Photos, and Documents"
  value       = module.storage.media_bucket_id
}

output "database_endpoint" {
  description = "RDS PostgreSQL Database Endpoint (Private inside VPC)"
  value       = module.database.db_endpoint
}

output "database_name" {
  description = "RDS PostgreSQL Database Name"
  value       = module.database.db_name
}

output "database_password_ssm_parameter" {
  description = "SSM Parameter Store Key containing the RDS Master Password"
  value       = module.database.db_password_ssm_param
}

output "lambda_functions" {
  description = "Names of the 5 Deployed Microservice Lambda Functions"
  value       = module.compute.lambda_function_names
}

output "cost_guardrail_budget" {
  description = "AWS Budgets Free Tier Guardrail Monitor"
  value       = module.monitoring.budget_name
}

output "data_tools_function_name" {
  description = "Snapshot Lambda: export and restore the database (scripts/snapshot_export.sh, snapshot_restore.sh)"
  value       = module.data_tools.data_tools_function_name
}
