terraform {
  required_version = ">= 1.5.0" // min version
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" //recent provider
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2" //for cloud-init
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5" // for ansible inventory
    }
  }
}
