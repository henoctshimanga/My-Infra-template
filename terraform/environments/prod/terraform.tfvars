# Production Environment Configuration

# Global Configuration
aws_region   = "us-west-2"
environment  = "prod"
project_name = "iac-solution"

# VPC Configuration
vpc_cidr           = "10.2.0.0/16"
az_count           = 3  # Multi-AZ for production
enable_nat_gateway = true
enable_vpn_gateway = false

# Security Configuration
enable_ssh_access = true
ssh_cidr_blocks   = ["10.0.0.0/8"]  # VPN/internal access only
enable_monitoring = true

# Compute Configuration
web_instance_count = 3
app_instance_count = 3
web_instance_type  = "t3.medium"
app_instance_type  = "t3.medium"
key_name          = ""  # Specify your key pair name

# Load Balancer Configuration
enable_load_balancer = true
lb_internal         = false
lb_type            = "application"

# Auto Scaling Configuration
enable_auto_scaling  = true
asg_min_size        = 2
asg_max_size        = 10
asg_desired_capacity = 3

# Database Configuration
enable_database                    = true
db_engine                         = "postgres"
db_engine_version                = "15.3"
db_instance_class                = "db.r6g.large"  # Better performance for prod
db_allocated_storage             = 100
db_storage_encrypted             = true
db_name                          = "proddb"
db_username                      = "dbadmin"
db_backup_retention_period       = 30  # Extended backup retention
db_backup_window                 = "03:00-04:00"
db_maintenance_window            = "sun:04:00-sun:05:00"
db_performance_insights_enabled  = true
db_monitoring_interval           = 15  # Enhanced monitoring
