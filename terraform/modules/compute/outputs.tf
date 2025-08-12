output "web_instance_ids" {
  description = "IDs of web server instances"
  value       = var.enable_auto_scaling ? [] : aws_instance.web[*].id
}

output "app_instance_ids" {
  description = "IDs of application server instances"
  value       = var.enable_auto_scaling ? [] : aws_instance.app[*].id
}

output "web_instance_public_ips" {
  description = "Public IP addresses of web servers"
  value       = var.enable_auto_scaling ? [] : aws_instance.web[*].public_ip
}

output "web_instance_private_ips" {
  description = "Private IP addresses of web servers"
  value       = var.enable_auto_scaling ? [] : aws_instance.web[*].private_ip
}

output "app_instance_private_ips" {
  description = "Private IP addresses of application servers"
  value       = var.enable_auto_scaling ? [] : aws_instance.app[*].private_ip
}

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].id : null
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].arn : null
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].zone_id : null
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = var.enable_load_balancer ? aws_lb_target_group.web[0].arn : null
}

output "web_launch_template_id" {
  description = "ID of the web server launch template"
  value       = aws_launch_template.web.id
}

output "app_launch_template_id" {
  description = "ID of the application server launch template"
  value       = aws_launch_template.app.id
}

output "web_autoscaling_group_name" {
  description = "Name of the web server Auto Scaling Group"
  value       = var.enable_auto_scaling ? aws_autoscaling_group.web[0].name : null
}

output "app_autoscaling_group_name" {
  description = "Name of the application server Auto Scaling Group"
  value       = var.enable_auto_scaling ? aws_autoscaling_group.app[0].name : null
}

output "web_autoscaling_group_arn" {
  description = "ARN of the web server Auto Scaling Group"
  value       = var.enable_auto_scaling ? aws_autoscaling_group.web[0].arn : null
}

output "app_autoscaling_group_arn" {
  description = "ARN of the application server Auto Scaling Group"
  value       = var.enable_auto_scaling ? aws_autoscaling_group.app[0].arn : null
}
