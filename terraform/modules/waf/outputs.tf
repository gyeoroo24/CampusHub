output "web_acl_arn" {
  description = "The ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.cloudfront_waf.arn
}

output "web_acl_id" {
  description = "The ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.cloudfront_waf.id
}
