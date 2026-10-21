# Managed authentication of the public API: an Amazon Cognito user pool per
# environment.
#
# Only an administrator creates accounts (no public sign-up). A user signs in
# with the app client below and gets an access token, which the API Gateway JWT
# authorizer (apigateway.tf) checks on every /api/* request.
# Essentials tier: 10 000 monthly active users free, with no end date.
resource "aws_cognito_user_pool" "this" {
  name                = local.name
  user_pool_tier      = "ESSENTIALS"
  deletion_protection = "INACTIVE"
  mfa_configuration   = "OFF"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }

  # No e-mail or SMS is ever sent: only an administrator resets a password.
  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  username_configuration {
    case_sensitive = false
  }
}

# Public client (no secret) used from the command line: USER_PASSWORD_AUTH
# sends the password to Cognito over HTTPS and returns the tokens.
resource "aws_cognito_user_pool_client" "api" {
  name         = "${local.name}-api"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 1
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
