# VPC Definition
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "campushub-${var.environment}-vpc"
  }
}

# Internet Gateway for Public Ingress (ALB) and Free Egress (No NAT Gateway charge)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "campushub-${var.environment}-igw"
  }
}

# Public Subnets across 3 AZs for Application Load Balancer
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "campushub-${var.environment}-public-subnet-${var.availability_zones[count.index]}"
    Tier = "PublicTier"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "campushub-${var.environment}-public-rt"
  }
}

# Route Table Association for Public Subnets
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Subnets for App Tier (EC2 Instances in Baseline / Lambda in Serverless)
resource "aws_subnet" "app" {
  count             = length(var.lambda_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.lambda_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "campushub-${var.environment}-app-subnet-${var.availability_zones[count.index]}"
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

# Route Table for App Subnets (Routes to IGW for zero-cost outbound to Cognito/packages; inbound locked by SG)
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "campushub-${var.environment}-app-rt"
  }
}

# Route Table Association for App Subnets
resource "aws_route_table_association" "app" {
  count          = length(aws_subnet.app)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
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
  route_table_ids   = [aws_route_table.app.id, aws_route_table.public.id]

  tags = {
    Name = "campushub-${var.environment}-s3-gateway-endpoint"
  }
}

# VPC Interface Endpoint for AWS Systems Manager (SSM Parameter Store private access)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
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
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "campushub-${var.environment}-kms-endpoint"
  }
}

# VPC Interface Endpoint for AWS Secrets Manager (the API Lambda reads the DB credentials secret)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "campushub-${var.environment}-secretsmanager-endpoint"
  }
}

# No VPC Interface Endpoint for Cognito Identity Provider (removed): AWS unconditionally blocks
# cognito-idp management-API calls (e.g. AdminGetUser, used by app/cognito_accounts.py to check a
# moderator candidate's sign-in account is still enabled) over PrivateLink once a user pool has any
# domain assigned for Hosted UI -- confirmed live, this pool's domain made every AdminGetUser call
# through this endpoint fail with "PrivateLink access is disabled for the user pool that has
# ManagedLogin configured", regardless of ManagedLoginVersion. There's no setting that re-enables
# it; the only fix is to not route this traffic through PrivateLink. The app subnets already have a
# direct IGW route (aws_route_table.app, below -- added for zero-cost pip/PyPI access), so dropping
# this endpoint just lets cognito-idp.<region>.amazonaws.com resolve publicly instead, which also
# still works fine for app/auth.py's plain-HTTPS JWKS fetch (that endpoint was never subject to the
# PrivateLink restriction above -- it's a public, unauthenticated well-known endpoint). Keeping an
# endpoint that can never work for this pool would just be a permanent ~$7-8/month for nothing.
