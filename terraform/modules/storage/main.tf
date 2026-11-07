resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ==========================================
# 1. FRONTEND STATIC HOSTING BUCKET (Flutter Web)
# ==========================================
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-${var.environment}-frontend-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-${var.environment}-frontend"
    Purpose = "Flutter Web Static Assets"
  }
}

# S3 Website Configuration for static Flutter Web SPA hosting
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Access block: If CloudFront is enabled, block all direct access (accessed via CloudFront OAC).
# If CloudFront is disabled, allow public read for direct S3 static website hosting.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = var.enable_cloudfront ? true : false
  block_public_policy     = var.enable_cloudfront ? true : false
  ignore_public_acls      = var.enable_cloudfront ? true : false
  restrict_public_buckets = var.enable_cloudfront ? true : false
}

# Direct public read policy for S3 Website Hosting when CloudFront is disabled
resource "aws_s3_bucket_policy" "frontend_public_website" {
  count  = var.enable_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObjectForWebsite"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# Server-side encryption for Frontend bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ==========================================
# 2. MEDIA & DOCUMENTS STORAGE BUCKET
# (Buy & Sell, Lost & Found, Academic Materials, Placement Docs)
# ==========================================
resource "aws_s3_bucket" "media" {
  bucket        = "${var.project_name}-${var.environment}-media-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.project_name}-${var.environment}-media"
    Purpose = "CampusHub User Uploads and Course Documents"
  }
}

# Block all direct public access (Accessed via CloudFront or Presigned URLs)
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning configuration for Media bucket (As per architecture diagram)
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with KMS/AES256 (NFR-7)
resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle configuration (Aborts incomplete multipart uploads & cleans noncurrent versions to save cost)
resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "cleanup-incomplete-and-old-versions"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# CORS configuration for direct browser uploads via presigned URLs
resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "HEAD"]
    # Only the web app: any other site gets no CORS headers, so it can't read or upload through it.
    allowed_origins = length(var.media_cors_origins) > 0 ? var.media_cors_origins : ["https://localhost"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
