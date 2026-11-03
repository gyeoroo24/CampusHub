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
    allow_headers     = ["*"]
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

  # Additional routes mapped to the FastAPI /api/v1 specification for Flutter Web
  frontend_v1_routes = {
    # Health check
    v1_health        = { route = "GET /api/v1/health", service = "community_events", auth = false }

    # S3 Upload Tickets
    v1_uploads_post  = { route = "POST /api/v1/uploads", service = "community_events", auth = false }
    v1_uploads_sub   = { route = "ANY /api/v1/uploads/{proxy+}", service = "community_events", auth = false }

    # Buy & Sell
    v1_bs_base       = { route = "ANY /api/v1/buy-sell", service = "buy_sell", auth = false }
    v1_bs_sub        = { route = "ANY /api/v1/buy-sell/{proxy+}", service = "buy_sell", auth = false }
    v1_listings_base = { route = "ANY /api/v1/listings", service = "buy_sell", auth = false }
    v1_listings_sub  = { route = "ANY /api/v1/listings/{proxy+}", service = "buy_sell", auth = false }
    v1_wanted_base   = { route = "ANY /api/v1/wanted", service = "buy_sell", auth = false }
    v1_wanted_sub    = { route = "ANY /api/v1/wanted/{proxy+}", service = "buy_sell", auth = false }

    # Lost & Found
    v1_lf_base       = { route = "ANY /api/v1/lost-found", service = "lost_found", auth = false }
    v1_lf_sub        = { route = "ANY /api/v1/lost-found/{proxy+}", service = "lost_found", auth = false }
    v1_lost_base     = { route = "ANY /api/v1/lost-reports", service = "lost_found", auth = false }
    v1_lost_sub      = { route = "ANY /api/v1/lost-reports/{proxy+}", service = "lost_found", auth = false }

    v1_found_base    = { route = "ANY /api/v1/found-reports", service = "lost_found", auth = false }
    v1_found_sub     = { route = "ANY /api/v1/found-reports/{proxy+}", service = "lost_found", auth = false }

    # Academic Hub
    v1_acad_sub      = { route = "ANY /api/v1/academic/{proxy+}", service = "academic_hub", auth = false }
    v1_dept_base     = { route = "ANY /api/v1/departments", service = "academic_hub", auth = false }
    v1_dept_sub      = { route = "ANY /api/v1/departments/{proxy+}", service = "academic_hub", auth = false }
    v1_courses_base  = { route = "ANY /api/v1/courses", service = "academic_hub", auth = false }
    v1_courses_sub   = { route = "ANY /api/v1/courses/{proxy+}", service = "academic_hub", auth = false }
    v1_materials_sub = { route = "ANY /api/v1/materials/{proxy+}", service = "academic_hub", auth = false }
    v1_feedback_sub  = { route = "ANY /api/v1/feedback/{proxy+}", service = "academic_hub", auth = false }

    # Community, Events, Profile, Auth & Landing Page Services
    v1_campus_svc_b  = { route = "ANY /api/v1/campus-services", service = "community_events", auth = false }
    v1_campus_svc_s  = { route = "ANY /api/v1/campus-services/{proxy+}", service = "community_events", auth = false }
    v1_events_base   = { route = "ANY /api/v1/events", service = "community_events", auth = false }
    v1_events_sub    = { route = "ANY /api/v1/events/{proxy+}", service = "community_events", auth = false }
    v1_event_tags_b  = { route = "ANY /api/v1/event-tags", service = "community_events", auth = false }
    v1_event_tags_s  = { route = "ANY /api/v1/event-tags/{proxy+}", service = "community_events", auth = false }
    v1_event_upd_s   = { route = "ANY /api/v1/event-updates/{proxy+}", service = "community_events", auth = false }
    v1_me_base       = { route = "ANY /api/v1/me", service = "community_events", auth = false }
    v1_me_sub        = { route = "ANY /api/v1/me/{proxy+}", service = "community_events", auth = false }
    v1_auth_sub      = { route = "ANY /api/v1/auth/{proxy+}", service = "community_events", auth = false }
    v1_messes_b      = { route = "ANY /api/v1/messes", service = "community_events", auth = false }
    v1_messes_s      = { route = "ANY /api/v1/messes/{proxy+}", service = "community_events", auth = false }
    v1_mess_menus_b  = { route = "ANY /api/v1/mess-menus", service = "community_events", auth = false }
    v1_mess_menus_s  = { route = "ANY /api/v1/mess-menus/{proxy+}", service = "community_events", auth = false }
    v1_seller_st_b   = { route = "ANY /api/v1/seller-strikes", service = "community_events", auth = false }
    v1_seller_st_s   = { route = "ANY /api/v1/seller-strikes/{proxy+}", service = "community_events", auth = false }

    # Messaging & Secure Chat
    v1_chat_base     = { route = "ANY /api/v1/chat", service = "community_events", auth = false }
    v1_chat_sub      = { route = "ANY /api/v1/chat/{proxy+}", service = "community_events", auth = false }

    # Admin Governance & Moderation
    v1_moderators_b  = { route = "ANY /api/v1/moderators", service = "community_events", auth = false }
    v1_moderators_s  = { route = "ANY /api/v1/moderators/{proxy+}", service = "community_events", auth = false }
    v1_reports_b     = { route = "ANY /api/v1/reports", service = "community_events", auth = false }
    v1_reports_s     = { route = "ANY /api/v1/reports/{proxy+}", service = "community_events", auth = false }
    v1_users_base    = { route = "ANY /api/v1/users", service = "community_events", auth = false }
    v1_users_sub     = { route = "ANY /api/v1/users/{proxy+}", service = "community_events", auth = false }

    # Forums
    v1_forums_s      = { route = "ANY /api/v1/forums/{proxy+}", service = "community_events", auth = false }
    v1_threads_s     = { route = "ANY /api/v1/threads/{proxy+}", service = "community_events", auth = false }
    v1_comments_s    = { route = "ANY /api/v1/comments/{proxy+}", service = "community_events", auth = false }

    # Placement Hub
    v1_placement_sub = { route = "ANY /api/v1/placement/{proxy+}", service = "placement_hub", auth = false }
    v1_companies_b   = { route = "ANY /api/v1/companies", service = "placement_hub", auth = false }
    v1_companies_s   = { route = "ANY /api/v1/companies/{proxy+}", service = "placement_hub", auth = false }
    v1_seniors_s     = { route = "ANY /api/v1/seniors/{proxy+}", service = "placement_hub", auth = false }
    v1_jds_s         = { route = "ANY /api/v1/jds/{proxy+}", service = "placement_hub", auth = false }
    v1_ppts_s        = { route = "ANY /api/v1/ppts/{proxy+}", service = "placement_hub", auth = false }
    v1_interviews_b  = { route = "ANY /api/v1/interviews", service = "placement_hub", auth = false }
    v1_interviews_s  = { route = "ANY /api/v1/interviews/{proxy+}", service = "placement_hub", auth = false }

    # Universal /api/v1 Catch-all fallback
    v1_catchall      = { route = "ANY /api/v1/{proxy+}", service = "community_events", auth = false }
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

# Routes dedicated to Flutter Web (/api/v1/*)
resource "aws_apigatewayv2_route" "frontend_v1_routes" {
  for_each = local.frontend_v1_routes

  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = each.value.route
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integrations[each.value.service].id}"
  authorization_type = each.value.auth ? "JWT" : "NONE"
  authorizer_id      = each.value.auth ? aws_apigatewayv2_authorizer.cognito_jwt.id : null
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
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
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
