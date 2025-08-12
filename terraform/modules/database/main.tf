# Database Module - RDS and related database infrastructure
# Manages PostgreSQL/MySQL RDS instances with security and monitoring

# Random password for database
resource "random_password" "master_password" {
  count = var.manage_master_user_password ? 0 : 1

  length  = 16
  special = true
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  })
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  family = var.engine == "postgres" ? "postgres15" : "mysql8.0"
  name   = "${var.project_name}-${var.environment}-db-params"

  dynamic "parameter" {
    for_each = var.engine == "postgres" ? var.postgres_parameters : var.mysql_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-db-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DB Option Group (for MySQL)
resource "aws_db_option_group" "main" {
  count = var.engine == "mysql" ? 1 : 0

  name                     = "${var.project_name}-${var.environment}-db-options"
  option_group_description = "Option group for ${var.project_name} ${var.environment}"
  engine_name              = "mysql"
  major_engine_version     = "8.0"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-db-options"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced Monitoring IAM Role
resource "aws_iam_role" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-rds-enhanced-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# KMS Key for RDS encryption
resource "aws_kms_key" "rds" {
  count = var.storage_encrypted ? 1 : 0

  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-rds-kms-key"
  })
}

resource "aws_kms_alias" "rds" {
  count = var.storage_encrypted ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-db"

  # Engine configuration
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Database configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type         = var.storage_type
  storage_encrypted    = var.storage_encrypted
  kms_key_id          = var.storage_encrypted ? aws_kms_key.rds[0].arn : null

  # Database credentials
  db_name  = var.db_name
  username = var.username
  password = var.manage_master_user_password ? null : (var.password != "" ? var.password : random_password.master_password[0].result)
  
  manage_master_user_password = var.manage_master_user_password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = var.publicly_accessible

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name   = var.engine == "mysql" ? aws_db_option_group.main[0].name : null

  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window
  copy_tags_to_snapshot  = true
  delete_automated_backups = var.delete_automated_backups

  # Snapshot configuration
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled && var.storage_encrypted ? aws_kms_key.rds[0].arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Multi-AZ and read replicas
  multi_az               = var.multi_az
  availability_zone     = var.multi_az ? null : var.availability_zone

  # Security and compliance
  deletion_protection = var.deletion_protection
  apply_immediately  = var.apply_immediately

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-database"
    Type = "database"
  })

  lifecycle {
    ignore_changes = [
      password,
    ]
  }
}

# Read Replica (optional)
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier = "${var.project_name}-${var.environment}-db-replica"

  # Replica configuration
  replicate_source_db = aws_db_instance.main.identifier

  # Instance configuration (can be different from master)
  instance_class = var.replica_instance_class != "" ? var.replica_instance_class : var.instance_class

  # Network configuration (can be in different AZ/region)
  availability_zone = var.replica_availability_zone
  publicly_accessible = var.replica_publicly_accessible

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  # Auto minor version upgrade
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Security
  deletion_protection = var.replica_deletion_protection

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-database-replica"
    Type = "database-replica"
  })
}

# CloudWatch Alarms for database monitoring
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.project_name}-${var.environment}-db-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS cpu utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  alarm_name          = "${var.project_name}-${var.environment}-db-free-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "2000000000"  # 2GB in bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-db-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = var.tags
}
