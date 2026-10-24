terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# AWS WAFv2 Web ACL for CloudFront (Must be provisioned in us-east-1)
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-${var.environment}-cloudfront-waf"
  description = "WAF protection for CampusHub CloudFront CDN"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: AWS Managed Common Rule Set (protects against OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: IP-based Rate Limiting (Phase 2 Item 7)
  rule {
    name     = "IPRateLimit"
    priority = 20

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPRateLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf-summary"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-waf"
  }
}
