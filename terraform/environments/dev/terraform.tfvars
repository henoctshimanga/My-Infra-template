# Development Environment Configuration

# Global Configuration
aws_region   = "us-west-2"
environment  = "dev"
project_name = "iac-solution"

# VPC Configuration
vpc_cidr           = "10.0.0.0/16"
az_count           = 2
enable_nat_gateway = true
enable_vpn_gateway = false

# Security Configuration
enable_ssh_access = true
ssh_cidr_blocks   = ["0.0.0.0/0"]  # Restrict in production
enable_monitoring = true

# Compute Configuration
web_instance_count = 1
app_instance_count = 1
web_instance_type  = "t3.micro"
app_instance_type  = "t3.micro"
key_name          = ""  # Specify your key pair name

# Load Balancer Configuration
enable_load_balancer = true
lb_internal         = false
lb_type            = "application"

# Auto Scaling Configuration
enable_auto_scaling  = false  # Disabled for dev to save costs
asg_min_size        = 1
asg_max_size        = 3
asg_desired_capacity = 1

# Database Configuration
enable_database                    = true
db_engine                         = "postgres"
db_engine_version                = "15.3"
db_instance_class                = "db.t3.micro"
db_allocated_storage             = 20
db_storage_encrypted             = true
db_name                          = "devdb"
db_username                      = "dbadmin"
db_backup_retention_period       = 1  # Minimal backup for dev
db_backup_window                 = "03:00-04:00"
db_maintenance_window            = "sun:04:00-sun:05:00"
db_performance_insights_enabled  = false
db_monitoring_interval           = 0
