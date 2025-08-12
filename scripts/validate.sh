#!/bin/bash

# Infrastructure Validation Script
# Validates Terraform and Ansible configurations

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation flags
VALIDATE_TERRAFORM=true
VALIDATE_ANSIBLE=true
VALIDATE_SECURITY=true
VALIDATE_LINT=true
VERBOSE=false

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate infrastructure code and configurations

OPTIONS:
    --skip-terraform        Skip Terraform validation
    --skip-ansible         Skip Ansible validation
    --skip-security        Skip security validation
    --skip-lint           Skip linting checks
    -v, --verbose         Verbose output
    -h, --help           Show this help message

EXAMPLES:
    $0                              # Run all validations
    $0 --skip-security             # Skip security scans
    $0 --skip-terraform -v         # Skip Terraform, verbose output
EOF
}

check_tools() {
    log_info "Checking required tools..."
    
    local missing_tools=()
    
    if [ "$VALIDATE_TERRAFORM" = true ]; then
        command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
        if command -v tfsec >/dev/null 2>&1; then
            log_info "tfsec found: $(tfsec --version)"
        else
            log_warning "tfsec not found - security scanning will be limited"
        fi
    fi
    
    if [ "$VALIDATE_ANSIBLE" = true ]; then
        command -v ansible >/dev/null 2>&1 || missing_tools+=("ansible")
        command -v ansible-playbook >/dev/null 2>&1 || missing_tools+=("ansible-playbook")
        if command -v ansible-lint >/dev/null 2>&1; then
            log_info "ansible-lint found: $(ansible-lint --version)"
        else
            log_warning "ansible-lint not found - linting will be limited"
        fi
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log_success "Tool check completed"
}

validate_terraform() {
    log_info "Validating Terraform configuration..."
    
    local terraform_dir="$PROJECT_ROOT/terraform"
    local validation_errors=0
    
    # Check if Terraform directory exists
    if [ ! -d "$terraform_dir" ]; then
        log_error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    cd "$terraform_dir"
    
    # Format check
    log_info "Checking Terraform formatting..."
    if ! terraform fmt -check=true -diff=true; then
        log_warning "Terraform files are not properly formatted"
        log_info "Run 'terraform fmt' to fix formatting issues"
        ((validation_errors++))
    else
        log_success "Terraform formatting is correct"
    fi
    
    # Initialize Terraform (required for validation)
    log_info "Initializing Terraform..."
    if ! terraform init -backend=false >/dev/null 2>&1; then
        log_error "Terraform initialization failed"
        cd - >/dev/null
        return 1
    fi
    
    # Validate configuration
    log_info "Validating Terraform configuration..."
    if ! terraform validate; then
        log_error "Terraform validation failed"
        ((validation_errors++))
    else
        log_success "Terraform validation passed"
    fi
    
    # Validate each environment configuration
    for env in dev staging prod; do
        local tfvars_file="environments/$env/terraform.tfvars"
        if [ -f "$tfvars_file" ]; then
            log_info "Validating $env environment configuration..."
            if ! terraform validate -var-file="$tfvars_file" >/dev/null 2>&1; then
                log_warning "Issues found in $env environment configuration"
                ((validation_errors++))
            else
                log_success "$env environment configuration is valid"
            fi
        else
            log_warning "Environment configuration not found: $tfvars_file"
        fi
    done
    
    # Validate modules
    for module_dir in modules/*/; do
        if [ -d "$module_dir" ]; then
            module_name=$(basename "$module_dir")
            log_info "Validating module: $module_name"
            
            cd "$module_dir"
            if [ -f "main.tf" ] || [ -f "*.tf" ]; then
                if ! terraform init -backend=false >/dev/null 2>&1; then
                    log_warning "Failed to initialize module: $module_name"
                    ((validation_errors++))
                elif ! terraform validate >/dev/null 2>&1; then
                    log_warning "Validation failed for module: $module_name"
                    ((validation_errors++))
                else
                    log_success "Module $module_name is valid"
                fi
            fi
            cd "$terraform_dir"
        fi
    done
    
    cd - >/dev/null
    
    if [ $validation_errors -eq 0 ]; then
        log_success "All Terraform validations passed"
        return 0
    else
        log_error "Terraform validation completed with $validation_errors errors/warnings"
        return 1
    fi
}

validate_ansible() {
    log_info "Validating Ansible configuration..."
    
    local ansible_dir="$PROJECT_ROOT/ansible"
    local validation_errors=0
    
    # Check if Ansible directory exists
    if [ ! -d "$ansible_dir" ]; then
        log_error "Ansible directory not found: $ansible_dir"
        return 1
    fi
    
    cd "$ansible_dir"
    
    # Check ansible.cfg
    if [ ! -f "ansible.cfg" ]; then
        log_warning "ansible.cfg not found"
        ((validation_errors++))
    else
        log_success "ansible.cfg found"
    fi
    
    # Validate inventory files
    log_info "Validating inventory files..."
    if [ -d "inventory" ]; then
        for inventory_file in inventory/*.yml inventory/*.ini; do
            if [ -f "$inventory_file" ]; then
                log_info "Checking inventory: $inventory_file"
                if ! ansible-inventory -i "$inventory_file" --list >/dev/null 2>&1; then
                    log_warning "Issues found in inventory: $inventory_file"
                    ((validation_errors++))
                else
                    log_success "Inventory $inventory_file is valid"
                fi
            fi
        done
    fi
    
    # Validate dynamic inventory script
    if [ -f "inventory/dynamic.py" ]; then
        log_info "Validating dynamic inventory script..."
        if python3 -m py_compile inventory/dynamic.py 2>/dev/null; then
            log_success "Dynamic inventory script syntax is correct"
        else
            log_error "Dynamic inventory script has syntax errors"
            ((validation_errors++))
        fi
    fi
    
    # Validate playbooks
    log_info "Validating playbooks..."
    if [ -d "playbooks" ]; then
        for playbook in playbooks/*.yml; do
            if [ -f "$playbook" ]; then
                playbook_name=$(basename "$playbook")
                log_info "Validating playbook: $playbook_name"
                
                if ! ansible-playbook --syntax-check "$playbook"; then
                    log_error "Syntax errors in playbook: $playbook_name"
                    ((validation_errors++))
                else
                    log_success "Playbook $playbook_name syntax is correct"
                fi
            fi
        done
    fi
    
    # Validate roles
    log_info "Validating roles..."
    if [ -d "roles" ]; then
        for role_dir in roles/*/; do
            if [ -d "$role_dir" ]; then
                role_name=$(basename "$role_dir")
                log_info "Validating role: $role_name"
                
                # Check role structure
                local role_issues=0
                for required_dir in tasks handlers; do
                    if [ ! -d "$role_dir/$required_dir" ]; then
                        log_warning "Role $role_name missing $required_dir directory"
                        ((role_issues++))
                    fi
                done
                
                # Check main task file
                if [ ! -f "$role_dir/tasks/main.yml" ]; then
                    log_warning "Role $role_name missing tasks/main.yml"
                    ((role_issues++))
                fi
                
                if [ $role_issues -eq 0 ]; then
                    log_success "Role $role_name structure is correct"
                else
                    ((validation_errors++))
                fi
            fi
        done
    fi
    
    cd - >/dev/null
    
    if [ $validation_errors -eq 0 ]; then
        log_success "All Ansible validations passed"
        return 0
    else
        log_error "Ansible validation completed with $validation_errors errors/warnings"
        return 1
    fi
}

validate_security() {
    log_info "Running security validation..."
    
    local security_errors=0
    
    # Terraform security scanning with tfsec
    if [ "$VALIDATE_TERRAFORM" = true ] && command -v tfsec >/dev/null 2>&1; then
        log_info "Running Terraform security scan with tfsec..."
        cd "$PROJECT_ROOT"
        
        if ! tfsec terraform/ --format=compact; then
            log_warning "Security issues found in Terraform configuration"
            ((security_errors++))
        else
            log_success "Terraform security scan passed"
        fi
        
        cd - >/dev/null
    fi
    
    # Check for sensitive data in files
    log_info "Scanning for sensitive data..."
    cd "$PROJECT_ROOT"
    
    # Patterns to search for
    local sensitive_patterns=(
        "password\s*=\s*[\"'].*[\"']"
        "secret\s*=\s*[\"'].*[\"']"
        "api_key\s*=\s*[\"'].*[\"']"
        "access_key\s*=\s*[\"'].*[\"']"
        "private_key\s*=\s*[\"'].*[\"']"
        "AKIA[0-9A-Z]{16}"  # AWS Access Key pattern
        "-----BEGIN.*PRIVATE KEY-----"
    )
    
    local sensitive_found=false
    for pattern in "${sensitive_patterns[@]}"; do
        if grep -r -E "$pattern" --exclude-dir=.git --exclude="*.log" . 2>/dev/null; then
            sensitive_found=true
        fi
    done
    
    if [ "$sensitive_found" = true ]; then
        log_error "Potential sensitive data found in files"
        ((security_errors++))
    else
        log_success "No obvious sensitive data found"
    fi
    
    # Check file permissions
    log_info "Checking file permissions..."
    find . -name "*.pem" -o -name "*.key" -o -name "*secret*" | while read -r file; do
        if [ -f "$file" ]; then
            local perms
            perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%A" "$file" 2>/dev/null)
            if [[ "$perms" =~ [0-7][0-7][4-7] ]]; then
                log_warning "File $file has overly permissive permissions: $perms"
                ((security_errors++))
            fi
        fi
    done
    
    cd - >/dev/null
    
    if [ $security_errors -eq 0 ]; then
        log_success "Security validation passed"
        return 0
    else
        log_error "Security validation completed with $security_errors issues"
        return 1
    fi
}

run_linting() {
    log_info "Running linting checks..."
    
    local lint_errors=0
    
    # Ansible linting
    if [ "$VALIDATE_ANSIBLE" = true ] && command -v ansible-lint >/dev/null 2>&1; then
        log_info "Running ansible-lint..."
        cd "$PROJECT_ROOT/ansible"
        
        if ! ansible-lint .; then
            log_warning "Ansible linting issues found"
            ((lint_errors++))
        else
            log_success "Ansible linting passed"
        fi
        
        cd - >/dev/null
    fi
    
    # YAML linting (if available)
    if command -v yamllint >/dev/null 2>&1; then
        log_info "Running YAML linting..."
        if ! yamllint -d relaxed . 2>/dev/null; then
            log_warning "YAML formatting issues found"
            ((lint_errors++))
        else
            log_success "YAML linting passed"
        fi
    fi
    
    # Shell script linting (if available)
    if command -v shellcheck >/dev/null 2>&1; then
        log_info "Running shell script linting..."
        find . -name "*.sh" -type f | while read -r script; do
            if ! shellcheck "$script"; then
                log_warning "Shell script issues found in: $script"
                ((lint_errors++))
            fi
        done
        
        if [ $lint_errors -eq 0 ]; then
            log_success "Shell script linting passed"
        fi
    fi
    
    if [ $lint_errors -eq 0 ]; then
        log_success "All linting checks passed"
        return 0
    else
        log_error "Linting completed with $lint_errors issues"
        return 1
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-terraform)
                VALIDATE_TERRAFORM=false
                shift
                ;;
            --skip-ansible)
                VALIDATE_ANSIBLE=false
                shift
                ;;
            --skip-security)
                VALIDATE_SECURITY=false
                shift
                ;;
            --skip-lint)
                VALIDATE_LINT=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
    
    log_info "Starting infrastructure validation..."
    
    local total_errors=0
    
    # Check required tools
    check_tools
    
    # Run validations
    if [ "$VALIDATE_TERRAFORM" = true ]; then
        if ! validate_terraform; then
            ((total_errors++))
        fi
    fi
    
    if [ "$VALIDATE_ANSIBLE" = true ]; then
        if ! validate_ansible; then
            ((total_errors++))
        fi
    fi
    
    if [ "$VALIDATE_SECURITY" = true ]; then
        if ! validate_security; then
            ((total_errors++))
        fi
    fi
    
    if [ "$VALIDATE_LINT" = true ]; then
        if ! run_linting; then
            ((total_errors++))
        fi
    fi
    
    # Summary
    echo
    if [ $total_errors -eq 0 ]; then
        log_success "All validations passed successfully!"
        exit 0
    else
        log_error "Validation completed with $total_errors categories having issues"
        log_info "Please review and fix the issues before deployment"
        exit 1
    fi
}

# Execute main function
main "$@"
