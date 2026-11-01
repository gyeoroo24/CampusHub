# VPC Definition
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "campushub-${var.environment}-vpc"
  }
}

# Private Subnets for Lambda Functions (App Tier)
resource "aws_subnet" "lambda" {
  count             = length(var.lambda_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.lambda_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "campushub-${var.environment}-lambda-private-subnet-${var.availability_zones[count.index]}"
    Tier = "AppTier"
  }
}

# Private Subnets for RDS Database Tier
resource "aws_subnet" "database" {
  count             = length(var.db_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "campushub-${var.environment}-db-private-subnet-${var.availability_zones[count.index]}"
    Tier = "DatabaseTier"
  }
}

# Route Table for Private Lambda Subnets
resource "aws_route_table" "lambda" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "campushub-${var.environment}-lambda-rt"
  }
}

# Route Table Association for Lambda Subnets
resource "aws_route_table_association" "lambda" {
  count          = length(aws_subnet.lambda)
  subnet_id      = aws_subnet.lambda[count.index].id
  route_table_id = aws_route_table.lambda.id
}

# Route Table for Database Subnets
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "campushub-${var.environment}-database-rt"
  }
}

# Route Table Association for Database Subnets
resource "aws_route_table_association" "database" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# VPC Gateway Endpoint for Amazon S3 (Free Tier compliant - No Hourly / Data Processing Charge)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.lambda.id]

  tags = {
    Name = "campushub-${var.environment}-s3-gateway-endpoint"
  }
}

# VPC Interface Endpoint for AWS Systems Manager (SSM Parameter Store private access)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.lambda[*].id
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "campushub-${var.environment}-ssm-endpoint"
  }
}

# VPC Interface Endpoint for AWS Key Management Service (KMS private decryption for SecureString)
resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.lambda[*].id
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "campushub-${var.environment}-kms-endpoint"
  }
}
