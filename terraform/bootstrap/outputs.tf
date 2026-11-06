output "state_bucket_name" {
  description = "The name of the S3 bucket created for Terraform remote state"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table created for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_config_snippet" {
  description = "Backend configuration block to paste into terraform/versions.tf"
  value       = <<EOT
backend "s3" {
  bucket         = "${aws_s3_bucket.terraform_state.id}"
  key            = "campushub/dev/terraform.tfstate"
  region         = "${var.aws_region}"
  dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
  encrypt        = true
}
EOT
}
