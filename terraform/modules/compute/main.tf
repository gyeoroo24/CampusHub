locals {
  # The 5 Lambda functions the module provisions. Every one runs the *same* zip — the real
  # backend/app FastAPI application (via Mangum), not a per-module reimplementation — so each is
  # independently capable of answering any request; API Gateway's routing to a particular one
  # (see modules/api_gateway) is about per-module metrics/scaling, not functional need. That's a
  # deliberate choice, not an accident: backend/app isn't split into 5 separately-deployable
  # codebases, and it doesn't need to be for this to work correctly.
  services = {
    buy_sell = {
      name        = "buy-sell"
      description = "CampusHub API (Buy & Sell routing)"
    }
    lost_found = {
      name        = "lost-found"
      description = "CampusHub API (Lost & Found routing)"
    }
    placement_hub = {
      name        = "placement-hub"
      description = "CampusHub API (Placement Hub routing)"
    }
    academic_hub = {
      name        = "academic-hub"
      description = "CampusHub API (Academic Help routing)"
    }
    community_events = {
      name        = "community-events"
      description = "CampusHub API (Community Events + everything else routing)"
    }
  }

  backend_dir = "${path.module}/../../../backend"
  build_dir   = "${path.module}/build/package"
}

# Rebuilds the deployment package whenever the trimmed requirements file or any app/ source file
# changes. (archive_file's own source_code_hash already makes Lambda redeploy when the zip's
# contents change; this trigger is what makes the zip's *contents* change in the first place.)
resource "null_resource" "build_lambda_package" {
  triggers = {
    requirements_hash = filesha256("${local.backend_dir}/requirements-lambda-zip.txt")
    app_hash = sha1(join("", [
      for f in sort(fileset(local.backend_dir, "app/**/*.py")) : filesha1("${local.backend_dir}/${f}")
    ]))
    build_script_hash = filesha256("${path.module}/build_lambda_zip.sh")
  }

  provisioner "local-exec" {
    command = "${path.module}/build_lambda_zip.sh ${local.backend_dir} ${local.build_dir}"
  }
}

# Package the built directory (real app + its trimmed dependencies — see build_lambda_zip.sh and
# backend/requirements-lambda-zip.txt) into the zip every one of the 5 Lambda functions deploys.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.build_dir
  output_path = "${path.module}/function.zip"
  depends_on  = [null_resource.build_lambda_package]
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

# Provision the 5 Lambda Functions in Private Subnets. Same zip, same handler, same env on all 5 —
# see the comment on local.services above for why.
resource "aws_lambda_function" "services" {
  for_each = local.services

  function_name = "${var.project_name}-${var.environment}-${each.value.name}"
  description   = each.value.description
  role          = aws_iam_role.lambda_exec.arn
  handler       = "app.main.handler"
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

  # Names and shapes here must match app/config.py's Settings fields (env_prefix="CAMPUSHUB_").
  environment {
    variables = {
      CAMPUSHUB_DATABASE_URL = "postgresql://${var.db_user}@${var.db_host}:5432/${var.db_name}"
      # The URL above carries no password: the real one is injected from Secrets Manager at
      # startup (app/db.py), so it's never in plaintext in the Lambda console or CloudWatch.
      CAMPUSHUB_DATABASE_SECRET_ARN = var.db_secret_arn
      # Not set: db_pool_max_size and db_statement_cache_size already default correctly on their
      # own (app/config.py resolves the pool size to 2 automatically once it detects it's running
      # in Lambda, via the AWS_LAMBDA_FUNCTION_NAME variable Lambda itself always sets).

      CAMPUSHUB_AUTH_MODE          = "cognito"
      CAMPUSHUB_COGNITO_REGION     = var.aws_region
      CAMPUSHUB_COGNITO_USER_POOL_ID  = var.cognito_user_pool_id
      CAMPUSHUB_COGNITO_APP_CLIENT_ID = var.cognito_app_client_id

      CAMPUSHUB_S3_BUCKET = var.media_bucket_id
      CAMPUSHUB_S3_REGION = var.aws_region

      # No matcher Lambda is deployed (zip-only deployment; the matcher needs the ML dependencies
      # this build intentionally leaves out — see requirements-lambda-zip.txt). match_mode="auto"
      # (the app's default) then resolves to "off": Lost & Found falls back to its same-category
      # rule, and auto-flagging's text checks skip the embedding-similarity part. Nothing crashes;
      # see app/config.py and app/categories_suggest.py's own "if missing, returns None" design.
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
