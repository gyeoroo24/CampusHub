# ==============================================================================
# CampusHub: IISc Student Community Platform - Terraform Root Configuration
# Team: Order of Phoenix (DS252 Introduction to Cloud Computing)
# ==============================================================================

# 1. NETWORKING TIER (VPC, Subnets across 3 AZs, S3 Gateway Endpoint, SGs)
module "networking" {
  source = "./modules/networking"

  environment = var.environment
  aws_region  = var.aws_region
}

# 2. DATABASE TIER (RDS PostgreSQL, Subnet Group, Parameter Group, SSM Params)
module "database" {
  source = "./modules/database"

  environment          = var.environment
  database_subnet_ids  = module.networking.database_subnet_ids
  db_security_group_id = module.networking.db_security_group_id
  db_name              = var.db_name
  db_username          = var.db_username
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  engine_version       = var.db_engine_version
  multi_az             = var.multi_az_db
}

# 3. STORAGE TIER (Frontend S3 Bucket, Media/Docs S3 Bucket, CORS, Encryption)
module "storage" {
  source = "./modules/storage"

  environment       = var.environment
  project_name      = var.project_name
  enable_cloudfront = var.enable_cloudfront
}

# 4. AUTHENTICATION TIER (Cognito User Pool, App Client, 4-Role Groups)
module "auth" {
  source = "./modules/auth"

  environment  = var.environment
  project_name = var.project_name
}

# 5. BACKEND APP TIER (5 Serverless FastAPI Lambda Microservices in VPC)
module "compute" {
  source = "./modules/compute"

  environment           = var.environment
  project_name          = var.project_name
  lambda_subnet_ids     = module.networking.lambda_subnet_ids
  app_security_group_id = module.networking.app_security_group_id
  db_host               = module.database.db_address
  db_name               = module.database.db_name
  db_user               = module.database.db_username
  db_password_ssm_param = module.database.db_password_ssm_param
  media_bucket_id       = module.storage.media_bucket_id
  media_bucket_arn      = module.storage.media_bucket_arn
  cognito_user_pool_id  = module.auth.user_pool_id
  lambda_memory_size    = var.lambda_memory_size
}

# 6. API GATEWAY TIER (HTTP API v2, Cognito JWT Authorizer, Routes, Throttling)
module "api_gateway" {
  source = "./modules/api_gateway"

  environment                 = var.environment
  project_name                = var.project_name
  cognito_user_pool_id        = module.auth.user_pool_id
  cognito_user_pool_client_id = module.auth.user_pool_client_id
  cognito_user_pool_endpoint  = module.auth.user_pool_endpoint
  lambda_invoke_arns          = module.compute.lambda_invoke_arns
  lambda_function_names       = module.compute.lambda_function_names
  throttling_rate_limit       = var.throttling_rate_limit
  throttling_burst_limit      = var.throttling_burst_limit
}

# 7. OPTIONAL EDGE SECURITY TIER (AWS WAFv2 - Toggleable to preserve Free Tier)
module "waf" {
  count  = var.enable_waf ? 1 : 0
  source = "./modules/waf"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  environment  = var.environment
  project_name = var.project_name
}

# 8. EDGE & CONTENT DELIVERY TIER (CloudFront CDN with OAC & Multi-Origin Routing)
module "cdn" {
  count  = var.enable_cloudfront ? 1 : 0
  source = "./modules/cdn"

  environment                          = var.environment
  project_name                         = var.project_name
  frontend_bucket_id                   = module.storage.frontend_bucket_id
  frontend_bucket_arn                  = module.storage.frontend_bucket_arn
  frontend_bucket_regional_domain_name = module.storage.frontend_bucket_regional_domain_name
  api_endpoint                         = module.api_gateway.api_endpoint
  web_acl_arn                          = var.enable_waf ? module.waf[0].web_acl_arn : ""
}

# Attach CloudFront Origin Access Control Policy to Frontend S3 Bucket (if CloudFront enabled)
resource "aws_s3_bucket_policy" "frontend_cloudfront_oac" {
  count  = var.enable_cloudfront ? 1 : 0
  bucket = module.storage.frontend_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${module.storage.frontend_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cdn[0].cloudfront_distribution_arn
          }
        }
      }
    ]
  })
}

# 9. MONITORING, TELEMETRY & COST CONTROL TIER (CloudWatch, Budgets, SNS)
module "monitoring" {
  source = "./modules/monitoring"

  environment           = var.environment
  project_name          = var.project_name
  alert_email           = var.alert_email
  monthly_budget_usd    = var.monthly_budget_usd
  api_id                = module.api_gateway.api_id
  db_instance_id        = module.database.db_instance_id
  lambda_function_names = module.compute.lambda_function_names
}
