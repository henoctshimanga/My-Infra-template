# Infrastructure as Code Makefile
# Usage: make <target> ENV=<environment>

.PHONY: help install-tools validate security-scan plan apply destroy configure docs clean

# Default environment
ENV ?= dev

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "Infrastructure as Code - Available Commands:"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

install-tools: ## Install required tools
	@echo "$(YELLOW)Installing required tools...$(NC)"
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)Terraform not found. Please install Terraform.$(NC)"; exit 1; }
	@command -v ansible >/dev/null 2>&1 || { echo "$(RED)Ansible not found. Please install Ansible.$(NC)"; exit 1; }
	@command -v tfsec >/dev/null 2>&1 || { echo "$(YELLOW)Installing tfsec...$(NC)"; go install github.com/aquasecurity/tfsec/cmd/tfsec@latest; }
	@command -v ansible-lint >/dev/null 2>&1 || { echo "$(YELLOW)Installing ansible-lint...$(NC)"; pip install ansible-lint; }
	@command -v terraform-docs >/dev/null 2>&1 || { echo "$(YELLOW)Installing terraform-docs...$(NC)"; go install github.com/terraform-docs/terraform-docs@latest; }
	@echo "$(GREEN)All tools installed successfully!$(NC)"

validate: ## Validate Terraform and Ansible code
	@echo "$(YELLOW)Validating infrastructure code...$(NC)"
	@./scripts/validate.sh

security-scan: ## Run security scans on infrastructure code
	@echo "$(YELLOW)Running security scans...$(NC)"
	@tfsec terraform/
	@ansible-lint ansible/

plan: validate ## Plan Terraform changes for specified environment
	@echo "$(YELLOW)Planning Terraform changes for $(ENV) environment...$(NC)"
	@cd terraform && terraform init -backend-config="key=terraform-$(ENV).tfstate"
	@cd terraform && terraform plan -var-file="environments/$(ENV)/terraform.tfvars"

apply: validate ## Apply Terraform changes for specified environment
	@echo "$(YELLOW)Applying Terraform changes for $(ENV) environment...$(NC)"
	@cd terraform && terraform init -backend-config="key=terraform-$(ENV).tfstate"
	@cd terraform && terraform apply -var-file="environments/$(ENV)/terraform.tfvars" -auto-approve
	@$(MAKE) generate-inventory ENV=$(ENV)

destroy: ## Destroy infrastructure for specified environment
	@echo "$(RED)Destroying infrastructure for $(ENV) environment...$(NC)"
	@read -p "Are you sure you want to destroy $(ENV) infrastructure? (y/N): " confirm && [ "$$confirm" = "y" ]
	@cd terraform && terraform destroy -var-file="environments/$(ENV)/terraform.tfvars" -auto-approve

generate-inventory: ## Generate Ansible inventory from Terraform outputs
	@echo "$(YELLOW)Generating Ansible inventory...$(NC)"
	@./scripts/generate_inventory.sh $(ENV)

configure: ## Run Ansible playbooks for specified environment
	@echo "$(YELLOW)Configuring servers for $(ENV) environment...$(NC)"
	@cd ansible && ansible-playbook -i inventory/$(ENV).ini playbooks/site.yml

deploy: ## Full deployment (plan, apply, configure)
	@echo "$(YELLOW)Starting full deployment for $(ENV) environment...$(NC)"
	@$(MAKE) plan ENV=$(ENV)
	@$(MAKE) apply ENV=$(ENV)
	@$(MAKE) configure ENV=$(ENV)
	@echo "$(GREEN)Deployment completed successfully!$(NC)"

docs: ## Generate documentation
	@echo "$(YELLOW)Generating documentation...$(NC)"
	@terraform-docs markdown table terraform/ > docs/TERRAFORM.md
	@terraform-docs markdown table terraform/modules/vpc/ > docs/modules/VPC.md
	@terraform-docs markdown table terraform/modules/compute/ > docs/modules/COMPUTE.md
	@terraform-docs markdown table terraform/modules/security/ > docs/modules/SECURITY.md
	@terraform-docs markdown table terraform/modules/database/ > docs/modules/DATABASE.md

clean: ## Clean temporary files
	@echo "$(YELLOW)Cleaning temporary files...$(NC)"
	@find . -name "*.tfplan" -delete
	@find . -name ".terraform" -type d -exec rm -rf {} +
	@find . -name "terraform.tfstate.backup" -delete

test: ## Run infrastructure tests
	@echo "$(YELLOW)Running infrastructure tests...$(NC)"
	@cd terraform && terraform fmt -check
	@cd terraform && terraform validate
	@ansible-lint ansible/
	@echo "$(GREEN)All tests passed!$(NC)"
