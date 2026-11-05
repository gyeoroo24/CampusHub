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

  # Read-heavy, browse-style GET endpoints (Locust at ~200 users showed the RDS connection pool
  # queueing on these): a short edge TTL absorbs repeat identical requests before they ever reach
  # the ALB/EC2/RDS -- ElastiCache (see modules/elasticache and backend/app/cache.py) then covers
  # the requests that still get to the origin, including ones CloudFront can't share across users.
  # POST/PUT/PATCH/DELETE to these same paths are untouched: cached_methods below is GET/HEAD only,
  # so mutations always pass straight through to the origin, cached or not.
  cacheable_api_path_patterns = [
    "/api/v1/buy-sell/*",
    "/api/v1/lost-found/*",
    "/api/v1/wanted/*",
    "/api/v1/events/*",
    "/api/v1/academics/*",
    "/api/v1/mess/*",
    "/api/v1/forums/*",
    "/api/v1/placement/*",
  ]
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

# Short-TTL cache policy for the read-heavy GET endpoints in cacheable_api_path_patterns above.
# The cache key includes Authorization so guests (no header) share one cached entry per query
# string while each signed-in caller's token gets its own -- no response is ever shared across two
# different Authorization values, so a personalized field (e.g. "is_bookmarked") can't leak between
# users. min_ttl=0 means an explicit Cache-Control from the origin would still be honored if added
# later; default/max stay short so a create/edit/delete is visible again quickly.
resource "aws_cloudfront_cache_policy" "api_short_ttl" {
  name        = "${var.project_name}-${var.environment}-api-short-ttl"
  comment     = "Short-TTL cache for read-heavy GET API endpoints (list/browse pages)"
  min_ttl     = 0
  default_ttl = 20
  max_ttl     = 60

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
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
  # Origin 2: Backend API (/api/*) - ALB or API Gateway
  # ==========================================
  origin {
    domain_name = local.api_gateway_domain
    origin_id   = "Backend-API-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.origin_protocol_policy
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    dynamic "custom_header" {
      for_each = var.origin_verify_header != "" ? [var.origin_verify_header] : []
      content {
        name  = "X-Origin-Verify"
        value = custom_header.value
      }
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

  # Ordered Cache Behaviors -> short-TTL edge cache for the read-heavy list/browse GET endpoints
  # (see locals.cacheable_api_path_patterns). CloudFront picks the first matching ordered_cache_behavior,
  # so these must be declared before the catch-all "/api/*" behavior below.
  dynamic "ordered_cache_behavior" {
    for_each = local.cacheable_api_path_patterns
    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = "Backend-API-Origin"
      viewer_protocol_policy = "https-only"
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id          = aws_cloudfront_cache_policy.api_short_ttl.id
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed AllViewerExceptHostHeader
    }
  }

  # Ordered Cache Behavior -> Routes all other /api/* traffic directly to Backend, uncached
  # (auth, uploads, chat, notifications, moderators, admin, reports, users/me, etc.)
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "Backend-API-Origin"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    # Managed CachingDisabled Policy ID
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # Managed AllViewerExceptHostHeader Policy ID
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  # No custom_error_response here: a CloudFront distribution's custom_error_response applies to
  # EVERY origin, not just the one it's commented for. A 403 fallback meant for S3 (deep links
  # like /events, now handled instead by the spa_rewrite function above, which only touches the
  # default/S3 behavior) also silently rewrote every real 403 the API origin returns -- e.g. a
  # deactivated account calling GET /me -- into a 200 response body containing index.html's raw
  # HTML, which the app then failed to parse as JSON. Removed rather than re-added, since the
  # function already covers the SPA routing case without touching /api/*.

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
