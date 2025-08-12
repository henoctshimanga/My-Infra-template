variable "project" {
  description = "Project name for tagging and resource naming"
  type        = string
  default     = "henoc_template"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS profile to use from your credentials file"
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of existing AWS key pair for SSH access (optional)"
  type        = string
  default     = null
}

variable "allow_ssh" {
  description = "Whether to allow SSH (port 22)"
  type        = bool
  default     = false
}

variable "ssh_ingress_cidr" {
  description = "CIDR for SSH access if allow_ssh = true"
  type        = string
  default     = "10.0.0.0/8"
}

variable "public_ingress_http" {
  description = "Allow HTTP (80) from internet"
  type        = bool
  default     = true
}

variable "public_ingress_https" {
  description = "Allow HTTPS (443) from internet"
  type        = bool
  default     = false
}

variable "app_secret_placeholder" {
  description = "Bootstrap secret placeholder (rotate after deployment)"
  type        = string
  default     = "CHANGE_ME_AFTER_DEPLOYMENT"
  sensitive   = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
