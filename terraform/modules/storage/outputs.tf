output "frontend_bucket_id" {
  description = "The ID/Name of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "The ARN of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_regional_domain_name" {
  description = "The regional domain name of the frontend S3 bucket for CloudFront origin"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "media_bucket_id" {
  description = "The ID/Name of the media S3 bucket"
  value       = aws_s3_bucket.media.id
}

output "media_bucket_arn" {
  description = "The ARN of the media S3 bucket"
  value       = aws_s3_bucket.media.arn
}

output "media_bucket_regional_domain_name" {
  description = "The regional domain name of the media S3 bucket"
  value       = aws_s3_bucket.media.bucket_regional_domain_name
}
