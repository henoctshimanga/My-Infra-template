#!/bin/bash

# Infrastructure Deployment Script
# Automates the full deployment process using Terraform and Ansible

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="/tmp/deployment-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
ACTION="deploy"
SKIP_VALIDATION=false
SKIP_TERRAFORM=false
SKIP_ANSIBLE=false
DRY_RUN=false
VERBOSE=false
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
AUTO_APPROVE=false

# Functions
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy infrastructure using Terraform and Ansible

OPTIONS:
    -e, --environment ENV       Environment to deploy (dev|staging|prod) [default: dev]
    -a, --action ACTION         Action to perform (plan|deploy|destroy) [default: deploy]
    -s, --skip-validation       Skip infrastructure validation
    -st, --skip-terraform       Skip Terraform execution
    -sa, --skip-ansible         Skip Ansible execution
    -d, --dry-run              Dry run mode (plan only)
    -v, --verbose              Verbose output
    -y, --auto-approve         Auto approve Terraform changes
    -h, --help                 Show this help message

EXAMPLES:
    $0 -e prod -a plan                    # Plan production deployment
    $0 -e staging --auto-approve          # Deploy to staging with auto-approve
    $0 -e dev -a destroy -y               # Destroy dev environment
    $0 --skip-terraform -e prod           # Run only Ansible on prod
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v ansible >/dev/null 2>&1 || missing_tools+=("ansible")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        log_info "Please configure AWS credentials using 'aws configure' or environment variables"
        exit 1
    fi
    
    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version')
    log_info "Using Terraform version: $tf_version"
    
    # Check Ansible version
    local ansible_version
    ansible_version=$(ansible --version | head -n1 | cut -d' ' -f2)
    log_info "Using Ansible version: $ansible_version"
    
    log_success "Prerequisites check completed"
}

validate_environment() {
    log_info "Validating environment: $ENVIRONMENT"
    
    # Check if environment-specific tfvars file exists
    local tfvars_file="$TERRAFORM_DIR/environments/$ENVIRONMENT/terraform.tfvars"
    if [ ! -f "$tfvars_file" ]; then
        log_error "Environment configuration not found: $tfvars_file"
        exit 1
    fi
    
    # Validate Terraform configuration
    if [ "$SKIP_TERRAFORM" = false ]; then
        log_info "Validating Terraform configuration..."
        cd "$TERRAFORM_DIR"
        terraform fmt -check=true -diff=true || {
            log_warning "Terraform files are not properly formatted"
            log_info "Run 'terraform fmt' to fix formatting issues"
        }
        terraform validate || {
            log_error "Terraform validation failed"
            exit 1
        }
        cd - >/dev/null
    fi
    
    # Validate Ansible configuration
    if [ "$SKIP_ANSIBLE" = false ]; then
        log_info "Validating Ansible configuration..."
        cd "$ANSIBLE_DIR"
        ansible-playbook --syntax-check playbooks/site.yml || {
            log_error "Ansible syntax validation failed"
            exit 1
        }
        cd - >/dev/null
    fi
    
    log_success "Environment validation completed"
}

init_terraform() {
    log_info "Initializing Terraform..."
    cd "$TERRAFORM_DIR"
    
    # Initialize with backend configuration
    terraform init \
        -backend-config="key=terraform-$ENVIRONMENT.tfstate" \
        -backend-config="region=${AWS_DEFAULT_REGION:-us-west-2}" \
        -reconfigure
    
    cd - >/dev/null
    log_success "Terraform initialized"
}

terraform_plan() {
    log_info "Creating Terraform execution plan..."
    cd "$TERRAFORM_DIR"
    
    local plan_file="terraform-$ENVIRONMENT.tfplan"
    local tfvars_file="environments/$ENVIRONMENT/terraform.tfvars"
    
    terraform plan \
        -var-file="$tfvars_file" \
        -out="$plan_file" \
        -detailed-exitcode || {
        local exit_code=$?
        if [ $exit_code -eq 1 ]; then
            log_error "Terraform plan failed"
            exit 1
        elif [ $exit_code -eq 2 ]; then
            log_info "Terraform plan shows changes to apply"
        fi
    }
    
    cd - >/dev/null
    log_success "Terraform plan completed"
}

terraform_apply() {
    log_info "Applying Terraform configuration..."
    cd "$TERRAFORM_DIR"
    
    local plan_file="terraform-$ENVIRONMENT.tfplan"
    local apply_args=()
    
    if [ "$AUTO_APPROVE" = true ]; then
        apply_args+=("-auto-approve")
    fi
    
    if [ -f "$plan_file" ]; then
        terraform apply "${apply_args[@]}" "$plan_file"
    else
        local tfvars_file="environments/$ENVIRONMENT/terraform.tfvars"
        terraform apply "${apply_args[@]}" -var-file="$tfvars_file"
    fi
    
    cd - >/dev/null
    log_success "Terraform apply completed"
}

terraform_destroy() {
    log_info "Destroying Terraform infrastructure..."
    cd "$TERRAFORM_DIR"
    
    local tfvars_file="environments/$ENVIRONMENT/terraform.tfvars"
    local destroy_args=("-var-file=$tfvars_file")
    
    if [ "$AUTO_APPROVE" = true ]; then
        destroy_args+=("-auto-approve")
    else
        log_warning "You are about to destroy infrastructure for environment: $ENVIRONMENT"
        read -p "Are you sure you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Destroy cancelled"
            exit 0
        fi
        destroy_args+=("-auto-approve")
    fi
    
    terraform destroy "${destroy_args[@]}"
    
    cd - >/dev/null
    log_success "Terraform destroy completed"
}

generate_ansible_inventory() {
    log_info "Generating Ansible inventory from Terraform outputs..."
    
    # Use the generate_inventory.sh script
    "$SCRIPT_DIR/generate_inventory.sh" "$ENVIRONMENT" || {
        log_error "Failed to generate Ansible inventory"
        exit 1
    }
    
    log_success "Ansible inventory generated"
}

run_ansible() {
    log_info "Running Ansible playbooks..."
    cd "$ANSIBLE_DIR"
    
    local inventory_file="inventory/$ENVIRONMENT.ini"
    local playbook_args=("-i" "$inventory_file")
    
    if [ "$VERBOSE" = true ]; then
        playbook_args+=("-v")
    fi
    
    # Add environment-specific variables
    playbook_args+=("-e" "environment=$ENVIRONMENT")
    playbook_args+=("-e" "project_name=iac-solution")
    
    # Check if inventory exists
    if [ ! -f "$inventory_file" ]; then
        log_warning "Static inventory not found, using dynamic inventory"
        inventory_file="inventory/dynamic.py"
        playbook_args=("-i" "$inventory_file")
        
        if [ "$VERBOSE" = true ]; then
            playbook_args+=("-v")
        fi
        playbook_args+=("-e" "environment=$ENVIRONMENT")
        playbook_args+=("-e" "project_name=iac-solution")
    fi
    
    # Run the main site playbook
    ansible-playbook "${playbook_args[@]}" playbooks/site.yml
    
    cd - >/dev/null
    log_success "Ansible playbooks completed"
}

run_health_checks() {
    log_info "Running health checks..."
    
    # Check if infrastructure is accessible
    cd "$TERRAFORM_DIR"
    local lb_dns
    lb_dns=$(terraform output -raw load_balancer_dns_name 2>/dev/null || echo "")
    
    if [ -n "$lb_dns" ]; then
        log_info "Testing load balancer accessibility: $lb_dns"
        
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if curl -s -o /dev/null -w "%{http_code}" "http://$lb_dns/health" | grep -q "200"; then
                log_success "Load balancer health check passed"
                break
            else
                log_info "Health check attempt $attempt/$max_attempts failed, retrying in 10 seconds..."
                sleep 10
                ((attempt++))
            fi
        done
        
        if [ $attempt -gt $max_attempts ]; then
            log_warning "Load balancer health check failed after $max_attempts attempts"
        fi
    else
        log_info "No load balancer found, skipping health check"
    fi
    
    cd - >/dev/null
    log_success "Health checks completed"
}

cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Clean up Terraform plan files
    if [ -d "$TERRAFORM_DIR" ]; then
        find "$TERRAFORM_DIR" -name "*.tfplan" -delete 2>/dev/null || true
    fi
    
    log_success "Cleanup completed"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -a|--action)
                ACTION="$2"
                shift 2
                ;;
            -s|--skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            -st|--skip-terraform)
                SKIP_TERRAFORM=true
                shift
                ;;
            -sa|--skip-ansible)
                SKIP_ANSIBLE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                ACTION="plan"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate environment argument
    case $ENVIRONMENT in
        dev|staging|prod)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
            exit 1
            ;;
    esac
    
    # Validate action argument
    case $ACTION in
        plan|deploy|destroy)
            ;;
        *)
            log_error "Invalid action: $ACTION. Must be one of: plan, deploy, destroy"
            exit 1
            ;;
    esac
    
    log_info "Starting deployment script"
    log_info "Environment: $ENVIRONMENT"
    log_info "Action: $ACTION"
    log_info "Log file: $LOG_FILE"
    
    # Set up error handling
    trap cleanup EXIT
    
    # Execute deployment steps
    check_prerequisites
    
    if [ "$SKIP_VALIDATION" = false ]; then
        validate_environment
    fi
    
    if [ "$SKIP_TERRAFORM" = false ]; then
        init_terraform
        
        case $ACTION in
            plan)
                terraform_plan
                ;;
            deploy)
                terraform_plan
                if [ "$DRY_RUN" = false ]; then
                    terraform_apply
                    generate_ansible_inventory
                fi
                ;;
            destroy)
                if [ "$DRY_RUN" = false ]; then
                    terraform_destroy
                fi
                ;;
        esac
    fi
    
    if [ "$SKIP_ANSIBLE" = false ] && [ "$ACTION" = "deploy" ] && [ "$DRY_RUN" = false ]; then
        run_ansible
        run_health_checks
    fi
    
    log_success "Deployment script completed successfully!"
    log_info "Check the log file for detailed output: $LOG_FILE"
}

# Execute main function
main "$@"
