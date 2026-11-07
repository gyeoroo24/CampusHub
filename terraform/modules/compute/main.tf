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

# Tesseract OCR layer for reading mess menus (optional; see tesseract_layer/build.sh). Layers are
# unzipped under /opt: /opt/bin is on PATH, /opt/lib is searched for shared libraries, and /opt/python
# is importable. The zip is over Lambda's 50 MB direct-upload limit, so it is staged in the media
# bucket under _layers/ and the layer is published from there.
resource "aws_s3_object" "tesseract_layer" {
  count       = var.tesseract_layer_zip == "" ? 0 : 1
  bucket      = var.media_bucket_id
  key         = "_layers/tesseract-${filemd5(var.tesseract_layer_zip)}.zip"
  source      = var.tesseract_layer_zip
  source_hash = filemd5(var.tesseract_layer_zip)
}

resource "aws_lambda_layer_version" "tesseract" {
  count                    = var.tesseract_layer_zip == "" ? 0 : 1
  layer_name               = "${var.project_name}-${var.environment}-tesseract"
  description              = "Tesseract 5.5.3 OCR, eng data, numpy, Pillow, pypdfium2 (x86_64, Python 3.11)"
  s3_bucket                = aws_s3_object.tesseract_layer[0].bucket
  s3_key                   = aws_s3_object.tesseract_layer[0].key
  source_code_hash         = filebase64sha256(var.tesseract_layer_zip)
  compatible_runtimes      = [var.lambda_runtime]
  compatible_architectures = ["x86_64"]
}

# ML layer for category suggestion (optional; see ml_layer/build.sh). Only buy_sell and lost_found carry it,
# and API Gateway sends the two /categories/suggest routes to them (modules/api_gateway): community-events
# can't, because its Tesseract layer already uses most of Lambda's 250 MB limit.
locals {
  ml_layer_services = var.ml_layer_zip == "" ? [] : ["buy_sell", "lost_found"]
}

resource "aws_s3_object" "ml_layer" {
  count       = var.ml_layer_zip == "" ? 0 : 1
  bucket      = var.media_bucket_id
  key         = "_layers/ml-${filemd5(var.ml_layer_zip)}.zip"
  source      = var.ml_layer_zip
  source_hash = filemd5(var.ml_layer_zip)
}

resource "aws_lambda_layer_version" "ml" {
  count                    = var.ml_layer_zip == "" ? 0 : 1
  layer_name               = "${var.project_name}-${var.environment}-ml"
  description              = "onnxruntime 1.16.3, tokenizers, numpy 1.26, bge-small-en-v1.5 (x86_64, Python 3.11)"
  s3_bucket                = aws_s3_object.ml_layer[0].bucket
  s3_key                   = aws_s3_object.ml_layer[0].key
  source_code_hash         = filebase64sha256(var.ml_layer_zip)
  compatible_runtimes      = [var.lambda_runtime]
  compatible_architectures = ["x86_64"]
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

  memory_size = each.key == "community_events" ? var.community_events_memory_size : var.lambda_memory_size
  timeout     = var.lambda_timeout

  # The OCR layer is only attached to community-events, which serves the mess menu routes.
  layers = concat(
    each.key == "community_events" && var.tesseract_layer_zip != "" ? [aws_lambda_layer_version.tesseract[0].arn] : [],
    contains(local.ml_layer_services, each.key) ? [aws_lambda_layer_version.ml[0].arn] : [],
  )

  # Hyperplane VPC Configuration (Access RDS and S3 Endpoint privately)
  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [var.app_security_group_id]
  }

  # Names and shapes here must match app/config.py's Settings fields (env_prefix="CAMPUSHUB_").
  environment {
    variables = merge({
      CAMPUSHUB_DATABASE_URL = "postgresql://${var.db_user}@${var.db_host}:5432/${var.db_name}"
      # The URL above carries no password: the real one is injected from Secrets Manager at
      # startup (app/db.py), so it's never in plaintext in the Lambda console or CloudWatch.
      CAMPUSHUB_DATABASE_SECRET_ARN = var.db_secret_arn
      # Not set: db_pool_max_size and db_statement_cache_size already default correctly on their
      # own (app/config.py resolves the pool size to 2 automatically once it detects it's running
      # in Lambda, via the AWS_LAMBDA_FUNCTION_NAME variable Lambda itself always sets).

      CAMPUSHUB_AUTH_MODE             = "cognito"
      CAMPUSHUB_COGNITO_REGION        = var.aws_region
      CAMPUSHUB_COGNITO_USER_POOL_ID  = var.cognito_user_pool_id
      CAMPUSHUB_COGNITO_APP_CLIENT_ID = var.cognito_app_client_id

      CAMPUSHUB_S3_BUCKET = var.media_bucket_id
      CAMPUSHUB_S3_REGION = var.aws_region
      # Presigned upload URLs must point at the regional host: the global host answers with a 307
      # redirect, which browsers refuse for cross-origin PUTs (the upload then fails with a network error).
      CAMPUSHUB_S3_ENDPOINT_URL = "https://s3.${var.aws_region}.amazonaws.com"

      # Origins allowed to call the API cross-origin (app/main.py); the web app itself is same-origin.
      CAMPUSHUB_CORS_ALLOW_ORIGINS = jsonencode(var.cors_allow_origins)

      # No matcher Lambda is deployed (zip-only deployment; the matcher needs the ML dependencies
      # this build intentionally leaves out — see requirements-lambda-zip.txt). match_mode="auto"
      # (the app's default) then resolves to "off": Lost & Found falls back to its same-category
      # rule, and auto-flagging's text checks skip the embedding-similarity part. Nothing crashes;
      # see app/config.py and app/categories_suggest.py's own "if missing, returns None" design.
      },
      # Web Push (FR-22, push.tf): the public key browsers subscribe with, and the sender to hand pushes to.
      var.enable_web_push ? {
        CAMPUSHUB_VAPID_PUBLIC_KEY_PARAMETER = local.vapid_public_param
        CAMPUSHUB_VAPID_SUBJECT              = var.vapid_subject
        CAMPUSHUB_PUSH_SENDER_FUNCTION       = local.push_sender_name
      } : {},
      # ElastiCache Redis (app/cache.py). Like the DB password, the AUTH token itself is never set
      # here -- only its secret's ARN, read from Secrets Manager at startup.
      var.redis_enabled ? {
        CAMPUSHUB_REDIS_HOST            = var.redis_host
        CAMPUSHUB_REDIS_PORT            = tostring(var.redis_port)
        CAMPUSHUB_REDIS_TLS             = "true"
        CAMPUSHUB_REDIS_AUTH_SECRET_ARN = var.redis_auth_secret_arn
      } : {},
      each.key == "community_events" && var.tesseract_layer_zip != "" ? { TESSDATA_PREFIX = "/opt/share/tessdata" } : {},
      # The ML layer's model sits in /opt/models. Only the bge category model is there, so Lost & Found
      # matching still resolves to "off" (it needs the matching models too).
    contains(local.ml_layer_services, each.key) ? { CAMPUSHUB_MATCH_MODEL_DIR = "/opt/models" } : {})
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
