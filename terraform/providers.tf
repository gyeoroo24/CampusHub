# Primary AWS Provider for Region ap-south-1 (Mumbai)
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CampusHub"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Team        = "Order of Phoenix"
      Course      = "DS252"
    }
  }
}

# Secondary AWS Provider for us-east-1 (Required exclusively for CloudFront WAF and ACM certificates)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "CampusHub"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Team        = "Order of Phoenix"
      Course      = "DS252"
    }
  }
}
