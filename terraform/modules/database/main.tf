# Generate a secure random password for the PostgreSQL master user
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# DB Subnet Group across the 3 private database subnets
resource "aws_db_subnet_group" "main" {
  name        = "campushub-${var.environment}-db-subnet-group"
  description = "Subnet group for CampusHub RDS PostgreSQL"
  subnet_ids  = var.database_subnet_ids

  tags = {
    Name = "campushub-${var.environment}-db-subnet-group"
  }
}

# PostgreSQL Parameter Group enforcing TLS 1.2+ (NFR-7)
resource "aws_db_parameter_group" "postgres16" {
  name        = "campushub-${var.environment}-pg16-params"
  family      = "postgres16"
  description = "CampusHub PostgreSQL 16 custom parameter group"

  # Force SSL / TLS in transit
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "campushub-${var.environment}-pg16-params"
  }
}

# PostgreSQL RDS Instance (Single-AZ by default for Free Tier; Multi-AZ configurable for benchmarks)
resource "aws_db_instance" "postgres" {
  identifier                  = "campushub-${var.environment}-db"
  engine                      = "postgres"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = var.max_allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  
  db_name                     = var.db_name
  username                    = var.db_username
  password                    = random_password.db_password.result
  port                        = 5432

  db_subnet_group_name        = aws_db_subnet_group.main.name
  parameter_group_name        = aws_db_parameter_group.postgres16.name
  vpc_security_group_ids      = [var.db_security_group_id]

  # Free Tier vs High Availability toggle
  multi_az                    = var.multi_az
  publicly_accessible         = false
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  backup_retention_period     = var.backup_retention_period
  backup_window               = "20:00-21:00"
  maintenance_window          = "Sun:21:00-Sun:22:00"
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : "campushub-${var.environment}-db-final-snapshot"

  deletion_protection         = false

  tags = {
    Name = "campushub-${var.environment}-db"
  }
}

# Securely store DB connection parameters in AWS SSM Parameter Store (Standard parameters are 100% Free)
resource "aws_ssm_parameter" "db_host" {
  name        = "/campushub/${var.environment}/db/host"
  description = "PostgreSQL Hostname"
  type        = "String"
  value       = aws_db_instance.postgres.address
}

resource "aws_ssm_parameter" "db_name" {
  name        = "/campushub/${var.environment}/db/name"
  description = "PostgreSQL Database Name"
  type        = "String"
  value       = var.db_name
}

resource "aws_ssm_parameter" "db_user" {
  name        = "/campushub/${var.environment}/db/user"
  description = "PostgreSQL Master Username"
  type        = "String"
  value       = var.db_username
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/campushub/${var.environment}/db/password"
  description = "PostgreSQL Master Password"
  type        = "SecureString"
  value       = random_password.db_password.result
}

# The API reads its DB credentials from Secrets Manager, not SSM: CAMPUSHUB_DATABASE_SECRET_ARN
# points at this secret, in the {"username": ..., "password": ...} shape app/config.py expects.
# (The SSM parameters above are kept for anything else that still reads them.)
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "/campushub/${var.environment}/db/credentials"
  description             = "PostgreSQL master credentials, read by the API Lambda at startup"
  recovery_window_in_days = 0

  tags = {
    Name = "campushub-${var.environment}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
  })
}
