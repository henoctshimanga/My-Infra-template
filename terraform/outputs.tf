# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# Security Outputs
output "web_security_group_id" {
  description = "ID of the web security group"
  value       = module.security.web_security_group_id
}

output "app_security_group_id" {
  description = "ID of the application security group"
  value       = module.security.app_security_group_id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = module.security.database_security_group_id
}

# Compute Outputs
output "web_instance_ids" {
  description = "IDs of web server instances"
  value       = module.compute.web_instance_ids
}

output "app_instance_ids" {
  description = "IDs of application server instances"
  value       = module.compute.app_instance_ids
}

output "web_instance_public_ips" {
  description = "Public IP addresses of web servers"
  value       = module.compute.web_instance_public_ips
  sensitive   = false
}

output "web_instance_private_ips" {
  description = "Private IP addresses of web servers"
  value       = module.compute.web_instance_private_ips
}

output "app_instance_private_ips" {
  description = "Private IP addresses of application servers"
  value       = module.compute.app_instance_private_ips
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.compute.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = module.compute.load_balancer_zone_id
}

# Database Outputs
output "database_endpoint" {
  description = "Database endpoint"
  value       = var.enable_database ? module.database[0].endpoint : null
  sensitive   = true
}

output "database_port" {
  description = "Database port"
  value       = var.enable_database ? module.database[0].port : null
}

output "database_name" {
  description = "Database name"
  value       = var.enable_database ? module.database[0].db_name : null
}

# Ansible Inventory Data
output "ansible_inventory" {
  description = "Ansible inventory data in JSON format"
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
              db_engine    = var.db_engine
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

# Environment-specific outputs for external systems
output "infrastructure_info" {
  description = "Infrastructure information for external systems"
  value = {
    environment = var.environment
    region      = var.aws_region
    vpc_id      = module.vpc.vpc_id
    
    networking = {
      vpc_cidr         = module.vpc.vpc_cidr_block
      public_subnets   = module.vpc.public_subnet_ids
      private_subnets  = module.vpc.private_subnet_ids
    }
    
    compute = {
      web_instances    = module.compute.web_instance_ids
      app_instances    = module.compute.app_instance_ids
      load_balancer    = module.compute.load_balancer_dns_name
    }
    
    database = var.enable_database ? {
      endpoint = module.database[0].endpoint
      port     = module.database[0].port
      engine   = var.db_engine
    } : null
  }
}
