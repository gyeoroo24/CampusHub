data "aws_caller_identity" "current" {}

# AWS Cognito User Pool for CampusHub Authentication
resource "aws_cognito_user_pool" "pool" {
  name = "${var.project_name}-${var.environment}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "CampusHub - Verify your IISc email address"
    email_message        = "Welcome to CampusHub! Your verification code is {####}."
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-user-pool"
  }
}

# Cognito User Pool Client for Flutter Web / Mobile App (Public Client - No Secret)
resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project_name}-${var.environment}-app-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = concat([
    "http://localhost:3000/",
    "http://localhost:8080/",
    "https://oauth.pstmn.io/v1/callback"
  ], var.additional_callback_urls)

  logout_urls = concat([
    "http://localhost:3000/",
    "http://localhost:8080/"
  ], var.additional_callback_urls)

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  id_token_validity      = 1
  access_token_validity  = 1
  refresh_token_validity = 30

  token_validity_units {
    id_token      = "hours"
    access_token  = "hours"
    refresh_token = "days"
  }
}

# Hosted UI: the sign-in and sign-up pages the web app redirects to (authorization code + PKCE).
resource "aws_cognito_user_pool_domain" "hosted_ui" {
  domain       = var.cognito_domain_prefix != "" ? var.cognito_domain_prefix : "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

# ==========================================
# 4-Role Permission Matrix Groups (FR-1, FR-2, FR-3)
# ==========================================
resource "aws_cognito_user_group" "guests" {
  name         = "Guest"
  user_pool_id = aws_cognito_user_pool.pool.id
  description  = "Unauthenticated / Read-only guest users"
  precedence   = 40
}

resource "aws_cognito_user_group" "signed_in" {
  name         = "Signed-in"
  user_pool_id = aws_cognito_user_pool.pool.id
  description  = "Verified IISc signed-in students and alumni"
  precedence   = 30
}

resource "aws_cognito_user_group" "moderator" {
  name         = "Moderator"
  user_pool_id = aws_cognito_user_pool.pool.id
  description  = "Module and department/course level content moderators"
  precedence   = 20
}

resource "aws_cognito_user_group" "admin" {
  name         = "Administrator"
  user_pool_id = aws_cognito_user_pool.pool.id
  description  = "Full system administrators"
  precedence   = 10
}
