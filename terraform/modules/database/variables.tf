variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for RDS subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

# Database Configuration
variable "engine" {
  description = "Database engine"
  type        = string
  default     = "postgres"
  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "Engine must be either 'postgres' or 'mysql'."
  }
}

variable "engine_version" {
  description = "Database engine version"
  type        = string
  default     = "15.3"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage for RDS instance (GB)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling (GB)"
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "Storage type for RDS instance"
  type        = string
  default     = "gp3"
}

variable "storage_encrypted" {
  description = "Enable storage encryption for RDS"
  type        = bool
  default     = true
}

# Database Credentials
variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "appdb"
}

variable "username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
}

variable "password" {
  description = "Database master password (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "manage_master_user_password" {
  description = "Set to true to allow RDS to manage the master user password in Secrets Manager"
  type        = bool
  default     = true
}

# Network Configuration
variable "publicly_accessible" {
  description = "Make the RDS instance publicly accessible"
  type        = bool
  default     = false
}

# Backup Configuration
variable "backup_retention_period" {
  description = "Database backup retention period (days)"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Database backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Database maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "delete_automated_backups" {
  description = "Delete automated backups when the DB instance is deleted"
  type        = bool
  default     = true
}

# Snapshot Configuration
variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting the DB"
  type        = bool
  default     = false
}

# Monitoring Configuration
variable "performance_insights_enabled" {
  description = "Enable Performance Insights for RDS"
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period (days)"
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval for RDS (seconds)"
  type        = number
  default     = 0
  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = []
}

# High Availability Configuration
variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Availability Zone for the DB instance (if not Multi-AZ)"
  type        = string
  default     = ""
}

# Security Configuration
variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Enable auto minor version upgrade"
  type        = bool
  default     = true
}

# Read Replica Configuration
variable "create_read_replica" {
  description = "Create a read replica"
  type        = bool
  default     = false
}

variable "replica_instance_class" {
  description = "Instance class for read replica"
  type        = string
  default     = ""
}

variable "replica_availability_zone" {
  description = "Availability Zone for read replica"
  type        = string
  default     = ""
}

variable "replica_publicly_accessible" {
  description = "Make the read replica publicly accessible"
  type        = bool
  default     = false
}

variable "replica_deletion_protection" {
  description = "Enable deletion protection for read replica"
  type        = bool
  default     = false
}

# Parameter Configuration
variable "postgres_parameters" {
  description = "PostgreSQL database parameters"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "log_statement"
      value = "all"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    },
    {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
  ]
}

variable "mysql_parameters" {
  description = "MySQL database parameters"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "general_log"
      value = "1"
    },
    {
      name  = "slow_query_log"
      value = "1"
    },
    {
      name  = "long_query_time"
      value = "2"
    }
  ]
}

# CloudWatch Alarms
variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
