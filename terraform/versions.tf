terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ============================================================================
  # REMOTE STATE BACKEND CONFIGURATION
  #
  # To enable remote state storage with team locking:
  # 1. Run terraform in `terraform/bootstrap/` to create the S3 bucket & DynamoDB table.
  # 2. Uncomment the block below and replace the bucket name with the bootstrap output.
  # 3. Run `terraform init -migrate-state`
  # ============================================================================
   backend "s3" {
     bucket         = "campushub-tfstate-3797456e"
     key            = "campushub/dev/terraform.tfstate"
     region         = "ap-south-1"
     dynamodb_table = "campushub-tf-locks"
     encrypt        = true
   }
}
