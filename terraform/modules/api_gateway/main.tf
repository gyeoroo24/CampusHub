# CloudWatch Log Group for API Gateway Access Logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}-http-api"
  retention_in_days = 7
}

# HTTP API (API Gateway v2)
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-${var.environment}-http-api"
  protocol_type = "HTTP"
  description   = "CampusHub Serverless HTTP API Gateway with JWT Auth"

  cors_configuration {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token"]
    max_age           = 300
    allow_credentials = false
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-http-api"
  }
}

# Cognito JWT Authorizer (Built directly into API Gateway - Zero Lambda Cost)
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "CognitoJWTAuthorizer"

  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = "https://${var.cognito_user_pool_endpoint}"
  }
}

# Mapping of module path prefix to compute service key
locals {
  module_routes = {
    buy_sell = {
      prefix      = "buy-sell"
      service_key = "buy_sell"
    }
    lost_found = {
      prefix      = "lost-found"
      service_key = "lost_found"
    }
    placement_hub = {
      prefix      = "placement"
      service_key = "placement_hub"
    }
    academic_hub = {
      prefix      = "academic"
      service_key = "academic_hub"
    }
    community_events = {
      prefix      = "events"
      service_key = "community_events"
    }
  }
}

# Lambda Proxy Integrations for the 5 Microservices
resource "aws_apigatewayv2_integration" "lambda_integrations" {
  for_each = local.module_routes

  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns[each.value.service_key]
  integration_method     = "POST"
  payload_format_version = "2.0"
  description            = "Integration for ${each.value.prefix} microservice"
}

# Root Landing Route (GET /) so visiting the base URL returns a 200 OK healthy status
resource "aws_apigatewayv2_route" "root_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations["community_events"].id}"
}

# Base Read Route for Guests (e.g. GET /api/buy-sell without trailing slash)
resource "aws_apigatewayv2_route" "public_read_base_routes" {
  for_each = local.module_routes

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /api/${each.value.prefix}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[each.key].id}"
}

# Public Read Route for Guests with subpaths (e.g. GET /api/buy-sell/items)
resource "aws_apigatewayv2_route" "public_read_routes" {
  for_each = local.module_routes

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /api/${each.value.prefix}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[each.key].id}"
}

# Protected Routes for Signed-in/Moderator/Admin Actions (Secured by Cognito JWT)
resource "aws_apigatewayv2_route" "protected_routes" {
  for_each = local.module_routes

  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "ANY /api/${each.value.prefix}/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integrations[each.key].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id

  depends_on = [
    aws_apigatewayv2_route.public_read_routes
  ]
}

# Grant API Gateway permission to invoke each Lambda function
resource "aws_lambda_permission" "api_gateway" {
  for_each = local.module_routes

  statement_id  = "AllowAPIGatewayInvoke-${each.value.service_key}"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names[each.value.service_key]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# API Gateway Stage with Rate Limiting & Access Logging (PRD Risk 1 Mitigation)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit  # 50 req/sec steady state
    throttling_burst_limit = var.throttling_burst_limit # 100 burst
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
    })
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-default-stage"
  }
}
