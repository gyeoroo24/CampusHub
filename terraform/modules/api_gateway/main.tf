# CloudWatch Log Group for API Gateway Access Logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}-http-api"
  retention_in_days = 7
}

# HTTP API (API Gateway v2)
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-${var.environment}-http-api"
  protocol_type = "HTTP"
  description   = "CampusHub HTTP API Gateway, proxying to the FastAPI backend's own routing"

  # The web app calls the API through CloudFront on its own origin, so it needs no CORS at all; only
  # the listed origins may call it cross-origin. With none listed, preflights reach the app, whose
  # own CORS settings (CAMPUSHUB_CORS_ALLOW_ORIGINS, the same list) answer them.
  dynamic "cors_configuration" {
    for_each = length(var.cors_allow_origins) > 0 ? [1] : []
    content {
      allow_origins     = var.cors_allow_origins
      allow_methods     = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
      allow_headers     = ["*"]
      max_age           = 300
      allow_credentials = false
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-http-api"
  }
}

# No Cognito JWT authorizer at the gateway: the app verifies the Cognito ID token itself on every
# request that needs one (app/auth.py, current_user / optional_user), the same way it does for
# local development and the EC2/Docker deployment path. Gatekeeping here too would be redundant at
# best (double verification of the same token) and wrong at worst — plenty of these routes are
# meant to work for signed-out guests (browsing listings, events, courses...), and a blanket
# gateway-level JWT requirement on a whole prefix can't express that per-endpoint distinction the
# way the app's own dependencies already do.

# Lambda Proxy Integrations — one per microservice Lambda (modules/compute). Every one of the 5
# Lambdas runs the complete real app, so any integration can answer any request; see the comment
# on local.services in modules/compute/main.tf.
resource "aws_apigatewayv2_integration" "lambda_integrations" {
  for_each = var.lambda_invoke_arns

  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value
  integration_method     = "POST"
  payload_format_version = "2.0"
  description            = "Integration for the ${each.key} Lambda"
}

locals {
  # Service each Lambda nominally "owns" requests not otherwise covered by a specific prefix below.
  default_service = "community_events"

  # Path prefixes that map cleanly to exactly one module Lambda, confirmed against the real
  # routers' own route paths (backend/app/routers/*.py) rather than guessed — this is what the
  # previous version of this file got wrong. Routed as both the bare prefix and prefix/{proxy+},
  # so e.g. "ANY /api/v1/listings" and "ANY /api/v1/listings/42" both match.
  #
  # Everything NOT listed here (auth, me, users, uploads, notifications, chat, moderators, reports,
  # forums/threads/comments, seller-strikes, categories, saved-searches, and anything added later)
  # still works correctly — it's served by the catch-all route at the bottom of this file, pointed
  # at default_service. Every Lambda can answer every route, so "not explicitly listed" never means
  # "not handled"; it only means "not split out for its own per-module Lambda metrics."
  owned_prefixes = {
    # Buy & Sell
    listings = "buy_sell"
    wanted   = "buy_sell"

    # Lost & Found
    lost-reports  = "lost_found"
    found-reports = "lost_found"

    # Placement Hub
    companies  = "placement_hub"
    interviews = "placement_hub"
    jds        = "placement_hub"
    placement  = "placement_hub"
    ppts       = "placement_hub"
    seniors    = "placement_hub"

    # Academic Help
    courses     = "academic_hub"
    departments = "academic_hub"
    materials   = "academic_hub"
    feedback    = "academic_hub"

    # Community Events
    events        = "community_events"
    event-tags    = "community_events"
    event-updates = "community_events"
    messes        = "community_events"
    mess-menus    = "community_events"
  }
}

resource "aws_apigatewayv2_route" "owned_prefix_base" {
  for_each = local.owned_prefixes

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /api/v1/${each.key}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[each.value].id}"
}

resource "aws_apigatewayv2_route" "owned_prefix_sub" {
  for_each = local.owned_prefixes

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /api/v1/${each.key}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[each.value].id}"
}

# Category suggestion needs the ML layer, which only the buy_sell and lost_found functions carry (see
# modules/compute/main.tf), so these two routes go there instead of the catch-all. API Gateway prefers
# the most specific route, so they win over "ANY /api/v1/{proxy+}".
locals {
  suggest_routes = {
    "buy-sell/categories/suggest"   = "buy_sell"
    "lost-found/categories/suggest" = "lost_found"
  }
}

resource "aws_apigatewayv2_route" "category_suggest" {
  for_each = local.suggest_routes

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /api/v1/${each.key}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[each.value].id}"
}

# Everything else under /api/v1 (and /api/v1 itself, with no sub-path) — the safety net that makes
# this robust to routes this file doesn't know about, present or future.
resource "aws_apigatewayv2_route" "catch_all" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /api/v1/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[local.default_service].id}"
}

resource "aws_apigatewayv2_route" "catch_all_base" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /api/v1"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[local.default_service].id}"
}

# Root landing route (GET /) so visiting the base URL returns something other than a 404.
resource "aws_apigatewayv2_route" "root_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integrations[local.default_service].id}"
}

# Grant API Gateway permission to invoke each Lambda function
resource "aws_lambda_permission" "api_gateway" {
  for_each = var.lambda_function_names

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# API Gateway Stage with Rate Limiting & Access Logging (PRD Risk 1 Mitigation)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit    = var.throttling_rate_limit
    throttling_burst_limit   = var.throttling_burst_limit
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
