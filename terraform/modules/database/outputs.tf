output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.postgres.id
}

output "db_endpoint" {
  description = "The connection endpoint for the PostgreSQL database"
  value       = aws_db_instance.postgres.endpoint
}

output "db_address" {
  description = "The hostname of the PostgreSQL database"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "The port of the PostgreSQL database"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "The name of the default database"
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "The master username for the database"
  value       = aws_db_instance.postgres.username
}

output "db_password_ssm_param" {
  description = "SSM Parameter Store name containing the master DB password"
  value       = aws_ssm_parameter.db_password.name
}

output "db_secret_arn" {
  description = "Secrets Manager secret ARN holding {username, password} for the API Lambda"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_connect_host" {
  description = "The host the API Lambdas should connect to: the RDS Proxy endpoint when enable_rds_proxy is true, otherwise the RDS instance directly. data_tools always uses db_address directly, bypassing the proxy."
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].endpoint : aws_db_instance.postgres.address
}

output "rds_proxy_enabled" {
  description = "Whether RDS Proxy is currently provisioned"
  value       = var.enable_rds_proxy
}
