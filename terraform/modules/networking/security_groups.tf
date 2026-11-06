# Security Group for Application Tier (Lambda Functions)
resource "aws_security_group" "app_sg" {
  name        = "campushub-${var.environment}-app-sg"
  description = "Security group for Lambda functions in private subnets"
  vpc_id      = aws_vpc.main.id

  # Allow HTTPS egress (for AWS S3 Gateway Endpoint and secure internal communications)
  egress {
    description = "Allow HTTPS outbound for S3 Gateway Endpoint and AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound PostgreSQL traffic to DB Security Group
  egress {
    description     = "Allow outbound PostgreSQL traffic to RDS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.db_sg.id]
  }

  # Allow outbound Redis traffic to the ElastiCache Security Group
  egress {
    description     = "Allow outbound Redis traffic to ElastiCache"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.redis_sg.id]
  }

  tags = {
    Name = "campushub-${var.environment}-app-sg"
  }
}

# Security Group for Database Tier (RDS PostgreSQL)
resource "aws_security_group" "db_sg" {
  name        = "campushub-${var.environment}-db-sg"
  description = "Security group for PostgreSQL RDS cluster / instance"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "campushub-${var.environment}-db-sg"
  }
}

# Ingress Rule for Database Tier from Application Tier
resource "aws_security_group_rule" "db_ingress_from_app" {
  type                     = "ingress"
  description              = "Allow PostgreSQL inbound from Lambda App Tier"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db_sg.id
  source_security_group_id = aws_security_group.app_sg.id
}

# Security Group for ElastiCache Redis (query cache for the Lambda app tier)
resource "aws_security_group" "redis_sg" {
  name        = "campushub-${var.environment}-redis-sg"
  description = "Security group for ElastiCache Redis cluster"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "campushub-${var.environment}-redis-sg"
  }
}

# Ingress Rule for Redis from Application Tier only (least privilege)
resource "aws_security_group_rule" "redis_ingress_from_app" {
  type                     = "ingress"
  description              = "Allow Redis inbound from Lambda App Tier"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis_sg.id
  source_security_group_id = aws_security_group.app_sg.id
}

# Security Group for VPC Interface Endpoints (SSM, KMS)
resource "aws_security_group" "vpce_sg" {
  name        = "campushub-${var.environment}-vpce-sg"
  description = "Security group for private VPC Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTPS inbound from Lambda App Tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  tags = {
    Name = "campushub-${var.environment}-vpce-sg"
  }
}
