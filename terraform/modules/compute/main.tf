locals {
  services = {
    buy_sell = {
      name        = "buy-sell"
      description = "CampusHub Buy & Sell Module"
    }
    lost_found = {
      name        = "lost-found"
      description = "CampusHub Lost & Found Module"
    }
    placement_hub = {
      name        = "placement-hub"
      description = "CampusHub Placement Hub Module"
    }
    academic_hub = {
      name        = "academic-hub"
      description = "CampusHub Academic Help Module"
    }
    community_events = {
      name        = "community-events"
      description = "CampusHub Community & Events Module"
    }
  }
}

# Package the starter Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/app.py"
  output_path = "${path.module}/lambda_src/function.zip"
}

# CloudWatch Log Groups for each microservice with cost-effective 7-day retention
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each          = local.services
  name              = "/aws/lambda/${var.project_name}-${var.environment}-${each.value.name}"
  retention_in_days = 7

  tags = {
    Service = each.value.name
  }
}

# Provision the 5 Lambda Functions in Private Subnets
resource "aws_lambda_function" "services" {
  for_each = local.services

  function_name = "${var.project_name}-${var.environment}-${each.value.name}"
  description   = each.value.description
  role          = aws_iam_role.lambda_exec.arn
  handler       = "app.lambda_handler"
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # Hyperplane VPC Configuration (Access RDS and S3 Endpoint privately)
  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [var.app_security_group_id]
  }

  environment {
    variables = {
      SERVICE_NAME           = each.value.name
      ENVIRONMENT            = var.environment
      DB_HOST                = var.db_host
      DB_NAME                = var.db_name
      DB_USER                = var.db_user
      DB_PASSWORD_SSM_PARAM  = var.db_password_ssm_param
      MEDIA_BUCKET           = var.media_bucket_id
      COGNITO_USER_POOL_ID   = var.cognito_user_pool_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy_attachment.lambda_app_permissions,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = {
    Name    = "${var.project_name}-${var.environment}-${each.value.name}"
    Service = each.value.name
  }
}
