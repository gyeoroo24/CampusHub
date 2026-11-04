# Data tools: exports and restores the CampusHub database from inside the VPC, so the same data can be
# copied between deployments. Export/restore are invoked by ../../scripts/snapshot_export.sh and
# ../../scripts/snapshot_restore.sh. The function only runs when invoked; it costs nothing when idle.

locals {
  function_name = "${var.project_name}-${var.environment}-data-tools"
  pg_layer_zip  = "${path.module}/pg_layer/pg-layer.zip"
}

data "archive_file" "handler" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src"
  output_path = "${path.module}/handler.zip"
}

# The PostgreSQL client layer. It is over Lambda's 50 MB direct limit only with the Tesseract-size
# payloads; this one is small, but it is staged in S3 the same way so both layers behave alike.
resource "aws_s3_object" "pg_layer" {
  bucket      = var.media_bucket_id
  key         = "_layers/pg-${filemd5(local.pg_layer_zip)}.zip"
  source      = local.pg_layer_zip
  source_hash = filemd5(local.pg_layer_zip)
}

resource "aws_lambda_layer_version" "pg" {
  layer_name               = "${var.project_name}-${var.environment}-pg-client"
  description              = "PostgreSQL 16 client (pg_dump, pg_restore, psql) for x86_64 Lambda"
  s3_bucket                = aws_s3_object.pg_layer.bucket
  s3_key                   = aws_s3_object.pg_layer.key
  source_code_hash         = filebase64sha256(local.pg_layer_zip)
  compatible_runtimes      = [var.lambda_runtime]
  compatible_architectures = ["x86_64"]
}

resource "aws_iam_role" "data_tools" {
  name = "${local.function_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.data_tools.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "data_tools" {
  name = "snapshot-access"
  role = aws_iam_role.data_tools.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DatabaseSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.db_secret_arn
      },
      {
        # Snapshots only: the function never touches uploads, which the scripts copy from the operator's machine.
        Sid      = "SnapshotObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${var.media_bucket_arn}/_snapshots/*"
      },
      {
        Sid      = "SnapshotBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.media_bucket_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "data_tools" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "data_tools" {
  function_name    = local.function_name
  description      = "CampusHub database snapshot export/restore (pg_dump/pg_restore inside the VPC)"
  role             = aws_iam_role.data_tools.arn
  handler          = "handler.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256
  memory_size      = 1024
  timeout          = 900
  layers           = [aws_lambda_layer_version.pg.arn]

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [var.app_security_group_id]
  }

  environment {
    variables = {
      DB_HOST      = var.db_host
      DB_NAME      = var.db_name
      SECRET_ARN   = var.db_secret_arn
      MEDIA_BUCKET = var.media_bucket_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.vpc_access,
    aws_iam_role_policy.data_tools,
    aws_cloudwatch_log_group.data_tools,
  ]
}
