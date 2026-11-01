# CloudFront Origin Access Control (OAC) for Frontend S3 Bucket
resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                              = "${var.project_name}-${var.environment}-frontend-oac"
  description                       = "OAC for CampusHub static frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Extract API Gateway domain name from endpoint URL
locals {
  api_gateway_domain = replace(replace(var.api_endpoint, "https://", ""), "/", "")
}

# CloudFront Function for Single-Page Application (SPA) client-side routing
resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.project_name}-${var.environment}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite SPA routes to /index.html without touching static assets or API routes"
  publish = true
  code    = <<-EOF
function handler(event) {
    var request = event.request;
    var uri = request.uri;
    if (!uri.includes('.')) {
        request.uri = '/index.html';
    }
    return request;
}
EOF
}

# CloudFront Distribution fronting both S3 Static Frontend and API Gateway
resource "aws_cloudfront_distribution" "distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CampusHub CDN Distribution (${var.environment})"
  default_root_object = "index.html"
  price_class         = var.price_class
  web_acl_id          = var.web_acl_arn != "" ? var.web_acl_arn : null

  # ==========================================
  # Origin 1: S3 Static Website (Flutter Web)
  # ==========================================
  origin {
    domain_name              = var.frontend_bucket_regional_domain_name
    origin_id                = "S3-Frontend-Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
  }

  # ==========================================
  # Origin 2: API Gateway HTTP API (/api/*)
  # ==========================================
  origin {
    domain_name = local.api_gateway_domain
    origin_id   = "APIGateway-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default Cache Behavior -> Serves Flutter Web SPA from S3
  default_cache_behavior {
    target_origin_id       = "S3-Frontend-Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Managed CachingOptimized Policy ID
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  # Ordered Cache Behavior -> Routes /api/* traffic directly to API Gateway
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "APIGateway-Origin"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    # Managed CachingDisabled Policy ID
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # Managed AllViewerExceptHostHeader Policy ID
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  # SPA Routing Fallback: Redirect S3 403 to index.html with 0 min TTL (does NOT rewrite 404 API responses)
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cdn"
  }
}
