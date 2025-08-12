# Simple Web Application Example
# This example demonstrates how to use the IaC solution modules to deploy a basic web application

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = local.common_tags
  }
}

# Local variables for common configuration
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Example     = "simple-web-app"
    ManagedBy   = "Terraform"
    Owner       = "DevOps Team"
  }
  
  # Calculate AZs to use
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Variables for this example
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "simple-web-app"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to use"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
  default     = ""
}

variable "enable_database" {
  description = "Enable RDS database"
  type        = bool
  default     = false
}

# VPC Module - Creates networking infrastructure
module "vpc" {
  source = "../../terraform/modules/vpc"
  
  environment        = var.environment
  project_name      = var.project_name
  vpc_cidr          = var.vpc_cidr
  availability_zones = local.azs
  enable_nat_gateway = true
  enable_vpn_gateway = false
  
  tags = local.common_tags
}

# Security Module - Creates security groups and rules
module "security" {
  source = "../../terraform/modules/security"
  
  environment = var.environment
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr_block
  
  # Allow SSH from your IP (update as needed)
  enable_ssh_access = true
  ssh_cidr_blocks   = ["0.0.0.0/0"]  # Restrict this in production
  enable_monitoring = true
  
  tags = local.common_tags
}

# Compute Module - Creates EC2 instances and load balancer
module "compute" {
  source = "../../terraform/modules/compute"
  
  environment = var.environment
  project_name = var.project_name
  
  # Network configuration
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  
  # Security groups
  web_security_group_id = module.security.web_security_group_id
  app_security_group_id = module.security.app_security_group_id
  
  # Instance configuration - simplified for demo
  web_instance_count = 2
  app_instance_count = 1
  web_instance_type  = var.instance_type
  app_instance_type  = var.instance_type
  
  # Key pair for SSH access
  key_name = var.key_name
  
  # Load balancer
  enable_load_balancer = true
  lb_internal         = false
  lb_type            = "application"
  
  # Disable auto-scaling for simplicity
  enable_auto_scaling  = false
  
  tags = local.common_tags
}

# Database Module - Optional RDS database
module "database" {
  count = var.enable_database ? 1 : 0
  
  source = "../../terraform/modules/database"
  
  environment = var.environment
  project_name = var.project_name
  
  # Network configuration
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security.database_security_group_id]
  
  # Database configuration - minimal for demo
  engine                = "postgres"
  engine_version       = "15.3"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_encrypted    = true
  
  # Database details
  db_name  = "${replace(var.project_name, "-", "")}db"
  username = "dbadmin"
  manage_master_user_password = true
  
  # Backup settings - minimal for demo
  backup_retention_period = 1
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Monitoring - disabled for cost savings in demo
  performance_insights_enabled = false
  monitoring_interval         = 0
  
  tags = local.common_tags
}

# Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.compute.load_balancer_dns_name
}

output "web_instance_public_ips" {
  description = "Public IP addresses of web servers"
  value       = module.compute.web_instance_public_ips
}

output "web_instance_private_ips" {
  description = "Private IP addresses of web servers"
  value       = module.compute.web_instance_private_ips
}

output "app_instance_private_ips" {
  description = "Private IP addresses of app servers"
  value       = module.compute.app_instance_private_ips
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = var.enable_database ? module.database[0].endpoint : null
  sensitive   = true
}

# Connection information for easy access
output "connection_info" {
  description = "Connection information for the deployed infrastructure"
  value = {
    load_balancer_url = "http://${module.compute.load_balancer_dns_name}"
    ssh_web_servers   = [
      for ip in module.compute.web_instance_public_ips : 
      "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}"
    ]
    ssh_app_servers = [
      for ip in module.compute.app_instance_private_ips : 
      "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}  # (via bastion or web server)"
    ]
    database_endpoint = var.enable_database ? module.database[0].endpoint : "No database deployed"
  }
}

# Ansible inventory output
output "ansible_inventory" {
  description = "Ansible inventory in JSON format"
  value = jsonencode({
    all = {
      children = {
        webservers = {
          hosts = {
            for idx, ip in module.compute.web_instance_public_ips :
            "web-${idx + 1}" => {
              ansible_host = ip
              ansible_user = "ubuntu"
              private_ip   = module.compute.web_instance_private_ips[idx]
              instance_id  = module.compute.web_instance_ids[idx]
            }
          }
        }
        appservers = {
          hosts = {
            for idx, ip in module.compute.app_instance_private_ips :
            "app-${idx + 1}" => {
              ansible_host = ip
              ansible_user = "ubuntu"
              private_ip   = ip
              instance_id  = module.compute.app_instance_ids[idx]
            }
          }
        }
        databases = var.enable_database ? {
          hosts = {
            database = {
              ansible_host = split(":", module.database[0].endpoint)[0]
              db_engine    = "postgres"
              db_port      = module.database[0].port
              db_name      = module.database[0].db_name
            }
          }
        } : {}
      }
      vars = {
        environment     = var.environment
        project_name    = var.project_name
        aws_region      = var.aws_region
        vpc_id          = module.vpc.vpc_id
        load_balancer_dns = module.compute.load_balancer_dns_name
      }
    }
  })
}
