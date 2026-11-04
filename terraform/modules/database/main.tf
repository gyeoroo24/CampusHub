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
  identifier            = "campushub-${var.environment}-db"
  engine                = "postgres"
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.postgres16.name
  vpc_security_group_ids = [var.db_security_group_id]

  # Free Tier vs High Availability toggle
  multi_az                    = var.multi_az
  publicly_accessible         = false
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  backup_retention_period   = var.backup_retention_period
  backup_window             = "20:00-21:00"
  maintenance_window        = "Sun:21:00-Sun:22:00"
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "campushub-${var.environment}-db-final-snapshot"

  deletion_protection = false

  # Ships the Postgres log (connection errors, slow queries, etc.) to CloudWatch Logs — applied
  # immediately, no reboot. The log group RDS creates for this is named after the resource below.
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name = "campushub-${var.environment}-db"
  }
}

# RDS auto-creates this log group on first export but leaves retention at "Never expire"; manage it
# here so logs don't accumulate (and bill for storage) forever.
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/campushub-${var.environment}-db/postgresql"
  retention_in_days = 7

  tags = {
    Name = "campushub-${var.environment}-db-postgresql-logs"
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

# ------------------------------------------------------------------------------------------------
# RDS Proxy (optional, toggle with enable_rds_proxy — see the root variable for cost notes).
#
# app/db.py's own comment says it keeps db_pool_max_size small "and lets RDS Proxy do the pooling"
# — but nothing here ever provisioned one, so under concurrent load each of the 5 Lambda functions'
# many execution environments opens its own direct connection, and db.t4g.micro's small
# max_connections ceiling gets exhausted (TooManyConnectionsError). This multiplexes those many
# small client connections down to a handful of real ones, with no app code change: only the
# CAMPUSHUB_DATABASE_URL host changes (see db_connect_host output), not the database engine itself.
# ------------------------------------------------------------------------------------------------

resource "aws_iam_role" "proxy" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "campushub-${var.environment}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "campushub-${var.environment}-rds-proxy-role"
  }
}

resource "aws_iam_role_policy" "proxy_secret_access" {
  count = var.enable_rds_proxy ? 1 : 0
  name  = "campushub-${var.environment}-rds-proxy-secret-access"
  role  = aws_iam_role.proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.db_credentials.arn
    }]
  })
}

# db_sg already allows ingress on 5432 from app_sg (see modules/networking/security_groups.tf).
# The proxy reuses app_sg as its own security group, so that existing rule already covers the
# proxy -> RDS leg; this adds the one missing leg, Lambda -> proxy, both members of the same SG.
resource "aws_security_group_rule" "app_sg_self_ingress_for_proxy" {
  count                    = var.enable_rds_proxy ? 1 : 0
  type                     = "ingress"
  description              = "Allow Lambdas to reach the RDS Proxy, which shares this security group"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.app_security_group_id
  source_security_group_id = var.app_security_group_id
}

# Pre-created (rather than left to the proxy to create on first log line) so retention is managed
# instead of defaulting to "Never expire" — debug_logging can be verbose (logs SQL statements).
resource "aws_cloudwatch_log_group" "rds_proxy" {
  count             = var.enable_rds_proxy ? 1 : 0
  name              = "/aws/rds/proxy/campushub-${var.environment}-proxy"
  retention_in_days = 7

  tags = {
    Name = "campushub-${var.environment}-rds-proxy-logs"
  }
}

resource "aws_db_proxy" "main" {
  count                  = var.enable_rds_proxy ? 1 : 0
  name                   = "campushub-${var.environment}-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy[0].arn
  vpc_subnet_ids         = var.database_subnet_ids
  vpc_security_group_ids = [var.app_security_group_id]
  require_tls            = true
  debug_logging          = true
  idle_client_timeout    = 1800

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  depends_on = [aws_cloudwatch_log_group.rds_proxy, aws_iam_role_policy.proxy_secret_access]

  tags = {
    Name = "campushub-${var.environment}-rds-proxy"
  }
}

resource "aws_db_proxy_default_target_group" "main" {
  count         = var.enable_rds_proxy ? 1 : 0
  db_proxy_name = aws_db_proxy.main[0].name

  connection_pool_config {
    max_connections_percent      = 90
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
  }
}

resource "aws_db_proxy_target" "main" {
  count                  = var.enable_rds_proxy ? 1 : 0
  db_proxy_name          = aws_db_proxy.main[0].name
  target_group_name      = aws_db_proxy_default_target_group.main[0].name
  db_instance_identifier = aws_db_instance.postgres.identifier
}
