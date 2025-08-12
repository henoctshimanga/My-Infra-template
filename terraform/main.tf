# Main Terraform configuration
# This file orchestrates all infrastructure modules

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment   = var.environment
      Project       = var.project_name
      ManagedBy     = "Terraform"
      CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Local values
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
  
  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  environment = var.environment
  project_name = var.project_name
  vpc_cidr = local.vpc_cidr
  availability_zones = local.azs
  enable_nat_gateway = var.enable_nat_gateway
  enable_vpn_gateway = var.enable_vpn_gateway
  
  tags = local.common_tags
}

# Security Module
module "security" {
  source = "./modules/security"

  environment = var.environment
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr_block
  
  # Security configuration
  enable_ssh_access = var.enable_ssh_access
  ssh_cidr_blocks = var.ssh_cidr_blocks
  enable_monitoring = var.enable_monitoring
  
  tags = local.common_tags
}

# Database Module
module "database" {
  source = "./modules/database"
  
  count = var.enable_database ? 1 : 0

  environment = var.environment
  project_name = var.project_name
  
  # Network configuration
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.security.database_security_group_id]
  
  # Database configuration
  engine = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_encrypted = var.db_storage_encrypted
  
  # Database credentials
  db_name = var.db_name
  username = var.db_username
  manage_master_user_password = true
  
  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window = var.db_backup_window
  maintenance_window = var.db_maintenance_window
  
  # Monitoring
  performance_insights_enabled = var.db_performance_insights_enabled
  monitoring_interval = var.db_monitoring_interval
  
  tags = local.common_tags
}

# Compute Module
module "compute" {
  source = "./modules/compute"

  environment = var.environment
  project_name = var.project_name
  
  # Network configuration
  vpc_id = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  
  # Security groups
  web_security_group_id = module.security.web_security_group_id
  app_security_group_id = module.security.app_security_group_id
  
  # Instance configuration
  web_instance_count = var.web_instance_count
  app_instance_count = var.app_instance_count
  web_instance_type = var.web_instance_type
  app_instance_type = var.app_instance_type
  
  # Key pair
  key_name = var.key_name
  
  # Load balancer configuration
  enable_load_balancer = var.enable_load_balancer
  lb_internal = var.lb_internal
  lb_type = var.lb_type
  
  # Auto Scaling
  enable_auto_scaling = var.enable_auto_scaling
  asg_min_size = var.asg_min_size
  asg_max_size = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  
  tags = local.common_tags
}
