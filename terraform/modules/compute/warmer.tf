# Keeps one instance of each function warm. A cold function needs 3-4 s on its first request (load the
# app, fetch the database secret, open a connection), which showed as a lag the first time someone
# switched to a module. Every few minutes EventBridge sends each function an API Gateway-shaped
# GET /api/v1/health, which goes through the real app and its database pool. It does not keep spare
# instances: several requests at once can still start a cold one (provisioned concurrency would, at a cost).
locals {
  warm_event = {
    version        = "2.0"
    routeKey       = "GET /api/v1/health"
    rawPath        = "/api/v1/health"
    rawQueryString = ""
    headers        = { host = "warmer", "user-agent" = "campushub-warmer" }
    requestContext = {
      http  = { method = "GET", path = "/api/v1/health", protocol = "HTTP/1.1", sourceIp = "127.0.0.1", userAgent = "campushub-warmer" }
      stage = "$default"
    }
    isBase64Encoded = false
  }
}

resource "aws_cloudwatch_event_rule" "warm" {
  count               = var.warm_schedule == "" ? 0 : 1
  name                = "${var.project_name}-${var.environment}-lambda-warm"
  description         = "Keeps the CampusHub API functions warm"
  schedule_expression = var.warm_schedule
}

resource "aws_cloudwatch_event_target" "warm" {
  for_each = var.warm_schedule == "" ? {} : local.services
  rule     = aws_cloudwatch_event_rule.warm[0].name
  arn      = aws_lambda_function.services[each.key].arn
  input    = jsonencode(local.warm_event)
}

resource "aws_lambda_permission" "warm" {
  for_each      = var.warm_schedule == "" ? {} : local.services
  statement_id  = "AllowEventBridgeWarm"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.services[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.warm[0].arn
}
