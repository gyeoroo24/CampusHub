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
