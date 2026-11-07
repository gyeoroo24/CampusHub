# Web Push sender (FR-22). The API Lambdas run in the VPC without internet access, so they can't reach the
# browsers' push services (FCM, Mozilla, Apple). This function runs outside the VPC, from the same
# package, with handler app.webpush.lambda_handler: the API invokes it with the subscriptions and the
# message (through the Lambda VPC endpoint) and gets back the subscriptions that are gone.
#
# The VAPID key pair lives in SSM (scripts/create_vapid_keys.sh): only this function reads the private
# key; the API reads the public key and gives it to browsers. Until the keys exist, push stays off.
locals {
  push_sender_name     = "${var.project_name}-${var.environment}-push-sender"
  vapid_private_param  = "/campushub/${var.environment}/push/vapid_private_key"
  vapid_public_param   = "/campushub/${var.environment}/push/vapid_public_key"
}

resource "aws_iam_role" "push_sender" {
  count = var.enable_web_push ? 1 : 0
  name  = "${local.push_sender_name}-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "push_sender_logs" {
  count      = var.enable_web_push ? 1 : 0
  role       = aws_iam_role.push_sender[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "push_sender_key" {
  count = var.enable_web_push ? 1 : 0
  name  = "read-vapid-private-key"
  role  = aws_iam_role.push_sender[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:${var.aws_region}:*:parameter${local.vapid_private_param}" },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = "*",
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com" } } },
    ]
  })
}

resource "aws_cloudwatch_log_group" "push_sender" {
  count             = var.enable_web_push ? 1 : 0
  name              = "/aws/lambda/${local.push_sender_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "push_sender" {
  count         = var.enable_web_push ? 1 : 0
  function_name = local.push_sender_name
  description   = "CampusHub Web Push sender (outside the VPC, so it can reach browser push services)"
  role          = aws_iam_role.push_sender[0].arn
  handler       = "app.webpush.lambda_handler"
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  memory_size = 256
  timeout     = 15

  environment {
    variables = {
      VAPID_PRIVATE_KEY_PARAMETER = local.vapid_private_param
      VAPID_SUBJECT               = var.vapid_subject
    }
  }

  depends_on = [aws_iam_role_policy_attachment.push_sender_logs, aws_cloudwatch_log_group.push_sender]
}

# The API Lambdas may invoke the sender, and nothing else.
resource "aws_iam_role_policy" "invoke_push_sender" {
  count = var.enable_web_push ? 1 : 0
  name  = "invoke-push-sender"
  role  = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = aws_lambda_function.push_sender[0].arn }]
  })
}

# Warm with an empty batch: loads the key and the crypto library, sends nothing. Its own rule:
# EventBridge allows only 5 targets per rule, and the API warm rule already has the 5 API Lambdas.
resource "aws_cloudwatch_event_rule" "warm_push_sender" {
  count               = var.enable_web_push && var.warm_schedule != "" ? 1 : 0
  name                = "${var.project_name}-${var.environment}-push-sender-warm"
  description         = "Keeps the CampusHub push-sender function warm"
  schedule_expression = var.warm_schedule
}

resource "aws_cloudwatch_event_target" "warm_push_sender" {
  count = var.enable_web_push && var.warm_schedule != "" ? 1 : 0
  rule  = aws_cloudwatch_event_rule.warm_push_sender[0].name
  arn   = aws_lambda_function.push_sender[0].arn
  input = jsonencode({ tokens = [] })
}

resource "aws_lambda_permission" "warm_push_sender" {
  count         = var.enable_web_push && var.warm_schedule != "" ? 1 : 0
  statement_id  = "AllowEventBridgeWarm"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.push_sender[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.warm_push_sender[0].arn
}
