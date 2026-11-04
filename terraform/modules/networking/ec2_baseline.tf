# ----------------------------------------------------------------------------------------------
# EC2 baseline networking (optional, toggle with enable_ec2_baseline).
#
# Entirely additive: nothing here renames, modifies, or is read by the existing Lambda/API Gateway
# resources above (aws_subnet.lambda, aws_route_table.lambda, app_sg, db_sg's existing rule). These
# subnets host the ALB and the EC2 Auto Scaling Group together. No NAT Gateway (~$32/month) — like
# the Lambda path's VPC endpoints avoid needing one, these subnets get a direct Internet Gateway
# route instead, matching the course's own Baseline-Architecture.md design: EC2 keeps a public IP
# for cheap egress (OS packages, pip), but security groups below, not subnet privacy, do the actual
# lockdown (only the ALB can reach instances, on port 8000 only; no SSH — admin is via SSM).
# ----------------------------------------------------------------------------------------------

resource "aws_internet_gateway" "ec2_baseline" {
  count  = var.enable_ec2_baseline ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "campushub-${var.environment}-ec2-baseline-igw"
  }
}

resource "aws_subnet" "ec2_baseline" {
  count                   = var.enable_ec2_baseline ? length(var.ec2_baseline_subnet_cidrs) : 0
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.ec2_baseline_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "campushub-${var.environment}-ec2-baseline-subnet-${var.availability_zones[count.index]}"
    Tier = "EC2BaselineTier"
  }
}

resource "aws_route_table" "ec2_baseline" {
  count  = var.enable_ec2_baseline ? 1 : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ec2_baseline[0].id
  }

  tags = {
    Name = "campushub-${var.environment}-ec2-baseline-rt"
  }
}

resource "aws_route_table_association" "ec2_baseline" {
  count          = var.enable_ec2_baseline ? length(aws_subnet.ec2_baseline) : 0
  subnet_id      = aws_subnet.ec2_baseline[count.index].id
  route_table_id = aws_route_table.ec2_baseline[0].id
}

# Public-facing: only the ALB gets a security group that accepts traffic from the internet. Cross
# references between alb_sg and ec2_app_sg are separate aws_security_group_rule resources below
# (not inline ingress/egress blocks) -- two SGs can't reference each other's ID inline, that's a
# dependency cycle Terraform can't resolve.
resource "aws_security_group" "alb_sg" {
  count       = var.enable_ec2_baseline ? 1 : 0
  name        = "campushub-${var.environment}-alb-sg"
  description = "Security group for the EC2 baseline internet-facing ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet (TLS terminates at CloudFront in front of this ALB)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "campushub-${var.environment}-alb-sg"
  }
}

# EC2 app tier: only reachable from the ALB, never directly from the internet, despite having a
# public IP for egress. No ingress rule at all exists for SSH; admin access is via SSM.
resource "aws_security_group" "ec2_app_sg" {
  count       = var.enable_ec2_baseline ? 1 : 0
  name        = "campushub-${var.environment}-ec2-app-sg"
  description = "Security group for the EC2 baseline Auto Scaling Group"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS egress: AWS APIs, Cognito JWKS, package manager mirrors"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP egress: OS package installs (dnf/pip mirrors not on HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "campushub-${var.environment}-ec2-app-sg"
  }
}

resource "aws_security_group_rule" "alb_egress_to_ec2_app" {
  count                    = var.enable_ec2_baseline ? 1 : 0
  type                     = "egress"
  description              = "Forward to the EC2 app tier"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb_sg[0].id
  source_security_group_id = aws_security_group.ec2_app_sg[0].id
}

resource "aws_security_group_rule" "ec2_app_ingress_from_alb" {
  count                    = var.enable_ec2_baseline ? 1 : 0
  type                     = "ingress"
  description              = "App traffic from the ALB only"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2_app_sg[0].id
  source_security_group_id = aws_security_group.alb_sg[0].id
}

# Additive: db_sg's pre-existing "ingress from app_sg" rule (security_groups.tf) is untouched. This
# just adds the two new legs the EC2 baseline needs: the DB accepting it, and it reaching the DB.
resource "aws_security_group_rule" "db_ingress_from_ec2_app" {
  count                    = var.enable_ec2_baseline ? 1 : 0
  type                     = "ingress"
  description              = "Allow PostgreSQL inbound from the EC2 baseline app tier"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db_sg.id
  source_security_group_id = aws_security_group.ec2_app_sg[0].id
}

resource "aws_security_group_rule" "ec2_app_egress_to_db" {
  count                    = var.enable_ec2_baseline ? 1 : 0
  type                     = "egress"
  description              = "PostgreSQL to the shared RDS instance"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2_app_sg[0].id
  source_security_group_id = aws_security_group.db_sg.id
}
