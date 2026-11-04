# A standalone CloudFront distribution fronting only the EC2 baseline's ALB -- separate from, and
# never modifying, the existing distribution in modules/cdn that fronts the serverless path. This
# exists so the two deployment modes are actually comparable for benchmarking: both get TLS
# termination and edge routing from CloudFront, instead of comparing "CloudFront+API Gateway" against
# "plain HTTP straight to an ALB".
#
# Single origin, no S3/SPA origin -- this is a pure reverse proxy in front of the ALB for API/load
# testing, not a second copy of the frontend.

resource "aws_cloudfront_distribution" "baseline" {
  enabled         = true
  comment         = "CampusHub EC2 baseline API CDN (${var.environment})"
  is_ipv6_enabled = true

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALB-Baseline-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # the ALB has no HTTPS listener; TLS terminates here
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_header
    }
  }

  default_cache_behavior {
    target_origin_id       = "ALB-Baseline-Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    # Managed CachingDisabled Policy ID: this fronts a live API, not static assets.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # Managed AllViewerExceptHostHeader Policy ID: forwards Authorization, cookies, query strings.
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
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
    Name = "campushub-${var.environment}-baseline-cdn"
  }
}
