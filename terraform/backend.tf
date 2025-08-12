# Backend configuration for Terraform state management
# This configuration should be customized per environment

terraform {
  backend "s3" {
    # Backend configuration is set via CLI or backend config files
    # Example for different environments:
    # 
    # Development:
    # bucket = "your-terraform-state-bucket"
    # key    = "terraform-dev.tfstate"
    # region = "us-west-2"
    # 
    # Staging:
    # bucket = "your-terraform-state-bucket" 
    # key    = "terraform-staging.tfstate"
    # region = "us-west-2"
    # 
    # Production:
    # bucket = "your-terraform-state-bucket"
    # key    = "terraform-prod.tfstate" 
    # region = "us-west-2"
    
    # Security and state locking
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    
    # Configure these via environment variables or backend config files:
    # AWS_ACCESS_KEY_ID
    # AWS_SECRET_ACCESS_KEY
    # Or use IAM roles for better security
  }
}

# Optional: Create the DynamoDB table for state locking
# This should be created once per AWS account/region
resource "aws_dynamodb_table" "terraform_state_lock" {
  count = var.environment == "dev" ? 1 : 0  # Create only in dev environment
  
  name           = "terraform-state-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Environment = "shared"
    Purpose     = "terraform-state-locking"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# S3 bucket for Terraform state (create manually or via separate terraform config)
# resource "aws_s3_bucket" "terraform_state" {
#   count  = var.environment == "dev" ? 1 : 0
#   bucket = "your-terraform-state-bucket-${random_id.bucket_suffix.hex}"
#   
#   lifecycle {
#     prevent_destroy = true
#   }
# }
# 
# resource "aws_s3_bucket_versioning" "terraform_state" {
#   count  = var.environment == "dev" ? 1 : 0
#   bucket = aws_s3_bucket.terraform_state[0].id
#   
#   versioning_configuration {
#     status = "Enabled"
#   }
# }
# 
# resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
#   count  = var.environment == "dev" ? 1 : 0
#   bucket = aws_s3_bucket.terraform_state[0].id
# 
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }
# 
# resource "random_id" "bucket_suffix" {
#   byte_length = 4
# }
