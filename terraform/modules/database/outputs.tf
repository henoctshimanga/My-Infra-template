output "db_instance_id" {
  description = "ID of the RDS instance"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "endpoint" {
  description = "Database endpoint"
  value       = aws_db_instance.main.endpoint
}

output "port" {
  description = "Database port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

output "username" {
  description = "Database master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "password" {
  description = "Database master password"
  value       = var.manage_master_user_password ? null : (var.password != "" ? var.password : random_password.master_password[0].result)
  sensitive   = true
}

output "master_user_secret_arn" {
  description = "ARN of the master user secret (when manage_master_user_password is true)"
  value       = var.manage_master_user_password ? aws_db_instance.main.master_user_secret[0].secret_arn : null
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

output "db_parameter_group_name" {
  description = "Name of the DB parameter group"
  value       = aws_db_parameter_group.main.name
}

output "db_option_group_name" {
  description = "Name of the DB option group"
  value       = var.engine == "mysql" ? aws_db_option_group.main[0].name : null
}

output "kms_key_id" {
  description = "KMS key ID used for encryption"
  value       = var.storage_encrypted ? aws_kms_key.rds[0].key_id : null
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  value       = var.storage_encrypted ? aws_kms_key.rds[0].arn : null
}

output "enhanced_monitoring_role_arn" {
  description = "ARN of the enhanced monitoring IAM role"
  value       = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
}

# Read Replica Outputs
output "read_replica_id" {
  description = "ID of the read replica"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].id : null
}

output "read_replica_endpoint" {
  description = "Endpoint of the read replica"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].endpoint : null
}

output "read_replica_port" {
  description = "Port of the read replica"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].port : null
}

# Connection Information (for applications)
output "connection_info" {
  description = "Database connection information"
  value = {
    endpoint = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    database = aws_db_instance.main.db_name
    username = aws_db_instance.main.username
    engine   = var.engine
  }
  sensitive = true
}

# CloudWatch Alarm ARNs
output "cpu_alarm_arn" {
  description = "ARN of the CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.cpu_utilization.arn
}

output "storage_alarm_arn" {
  description = "ARN of the free storage space alarm"
  value       = aws_cloudwatch_metric_alarm.free_storage_space.arn
}

output "connections_alarm_arn" {
  description = "ARN of the database connections alarm"
  value       = aws_cloudwatch_metric_alarm.database_connections.arn
}
