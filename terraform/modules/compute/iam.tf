# IAM Role for Lambda Microservices
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-${var.environment}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS standard VPC Access Execution Role (allows VPC ENI creation & CloudWatch logging)
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Least-privilege inline policy for S3 Media access & SSM Parameter Store access
resource "aws_iam_policy" "lambda_app_permissions" {
  name        = "${var.project_name}-${var.environment}-lambda-app-permissions"
  description = "Permissions for CampusHub Lambdas to access S3 media and SSM parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3MediaBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.media_bucket_arn,
          "${var.media_bucket_arn}/*"
        ]
      },
      {
        Sid    = "SSMParameterStoreAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/campushub/${var.environment}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_app_permissions" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_app_permissions.arn
}
