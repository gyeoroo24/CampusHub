# Security Group for Application Load Balancer (ALB) Ingress
resource "aws_security_group" "alb_sg" {
  name        = "campushub-${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # Ingress from CloudFront CDN / Internet
  ingress {
    description = "Allow HTTP inbound from CloudFront"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS inbound from CloudFront"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Forward traffic to EC2 App Tier on port 8000
  egress {
    description = "Allow outbound to EC2 App Tier"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "campushub-${var.environment}-alb-sg"
  }
}

# Security Group for Application Tier (EC2 Instances in Baseline / Lambda in Serverless)
resource "aws_security_group" "app_sg" {
  name        = "campushub-${var.environment}-app-sg"
  description = "Security group for application compute tier"
  vpc_id      = aws_vpc.main.id

  # Ingress strictly from ALB on port 8000
  ingress {
    description     = "Allow HTTP inbound strictly from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow HTTPS egress (for S3 Gateway Endpoint, Cognito JWKS, Secrets Manager, etc.)
  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP egress (for package downloads / repositories)
  egress {
    description = "Allow HTTP outbound for OS packages"
    from_port   = 80
    to_port     = 80
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
