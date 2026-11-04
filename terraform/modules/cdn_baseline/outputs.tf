output "cloudfront_domain_name" {
  description = "Domain name of the EC2 baseline's CloudFront distribution"
  value       = aws_cloudfront_distribution.baseline.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the EC2 baseline's CloudFront distribution (for cache invalidation)"
  value       = aws_cloudfront_distribution.baseline.id
}
