#!/bin/bash

# Generate Ansible Inventory from Terraform Outputs
# This script reads Terraform outputs and creates Ansible inventory files

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
OUTPUT_FORMAT="ini"
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
Usage: $0 [ENVIRONMENT] [OPTIONS]

Generate Ansible inventory from Terraform outputs

ARGUMENTS:
    ENVIRONMENT     Environment name (dev|staging|prod) [default: dev]

OPTIONS:
    -f, --format FORMAT    Output format (ini|yaml|json) [default: ini]
    -v, --verbose         Verbose output
    -h, --help           Show this help message

EXAMPLES:
    $0 prod                      # Generate inventory for prod environment
    $0 dev --format yaml         # Generate YAML inventory for dev
    $0 staging -v               # Generate with verbose output
EOF
}

check_terraform_state() {
    log_info "Checking Terraform state for environment: $ENVIRONMENT"
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform to ensure state backend is accessible
    if ! terraform init -backend-config="key=terraform-$ENVIRONMENT.tfstate" >/dev/null 2>&1; then
        log_error "Failed to initialize Terraform backend"
        return 1
    fi
    
    # Check if state exists
    if ! terraform show >/dev/null 2>&1; then
        log_error "No Terraform state found for environment: $ENVIRONMENT"
        log_info "Please run 'terraform apply' first"
        return 1
    fi
    
    cd - >/dev/null
    log_success "Terraform state is accessible"
}

get_terraform_outputs() {
    log_info "Retrieving Terraform outputs..."
    
    cd "$TERRAFORM_DIR"
    
    # Get all outputs as JSON
    local outputs
    outputs=$(terraform output -json 2>/dev/null)
    
    if [ -z "$outputs" ] || [ "$outputs" = "{}" ]; then
        log_warning "No Terraform outputs found"
        echo "{}"
        return 0
    fi
    
    echo "$outputs"
    cd - >/dev/null
}

parse_outputs_to_inventory() {
    local outputs="$1"
    local format="$2"
    
    log_info "Parsing Terraform outputs to inventory format..."
    
    # Extract key information using jq
    local ansible_inventory_json
    ansible_inventory_json=$(echo "$outputs" | jq -r '.ansible_inventory.value // empty')
    
    if [ -n "$ansible_inventory_json" ] && [ "$ansible_inventory_json" != "null" ]; then
        # Use the pre-formatted ansible inventory from Terraform
        if [ "$VERBOSE" = true ]; then
            log_info "Using pre-formatted inventory from Terraform outputs"
        fi
        
        case $format in
            ini)
                convert_json_to_ini "$ansible_inventory_json"
                ;;
            yaml)
                convert_json_to_yaml "$ansible_inventory_json"
                ;;
            json)
                echo "$ansible_inventory_json" | jq '.'
                ;;
        esac
    else
        # Build inventory from individual outputs
        log_info "Building inventory from individual outputs"
        build_inventory_from_outputs "$outputs" "$format"
    fi
}

convert_json_to_ini() {
    local json_inventory="$1"
    
    # Parse JSON and convert to INI format
    python3 << EOF
import json
import sys

try:
    inventory = json.loads('''$json_inventory''')
except json.JSONDecodeError:
    print("Error: Invalid JSON inventory data", file=sys.stderr)
    sys.exit(1)

def write_group(group_name, group_data):
    if 'hosts' in group_data and group_data['hosts']:
        print(f"[{group_name}]")
        for host, host_vars in group_data['hosts'].items():
            if isinstance(host_vars, dict) and 'ansible_host' in host_vars:
                line = f"{host} ansible_host={host_vars['ansible_host']}"
                if 'ansible_user' in host_vars:
                    line += f" ansible_user={host_vars['ansible_user']}"
                print(line)
            else:
                print(host)
        print()
        
        # Write group variables
        if 'vars' in group_data and group_data['vars']:
            print(f"[{group_name}:vars]")
            for var, value in group_data['vars'].items():
                print(f"{var}={value}")
            print()

# Process all groups
if 'all' in inventory and 'children' in inventory['all']:
    children = inventory['all']['children']
    
    for group_name, group_data in children.items():
        write_group(group_name, group_data)

# Write global variables
if 'all' in inventory and 'vars' in inventory['all']:
    print("[all:vars]")
    for var, value in inventory['all']['vars'].items():
        print(f"{var}={value}")
EOF
}

convert_json_to_yaml() {
    local json_inventory="$1"
    
    # Convert JSON to YAML
    echo "$json_inventory" | python3 -c "
import json
import sys
import yaml

try:
    data = json.load(sys.stdin)
    print(yaml.dump(data, default_flow_style=False))
except Exception as e:
    print(f'Error converting to YAML: {e}', file=sys.stderr)
    sys.exit(1)
"
}

build_inventory_from_outputs() {
    local outputs="$1"
    local format="$2"
    
    log_info "Building inventory from individual Terraform outputs..."
    
    # Extract individual outputs
    local web_ips app_ips db_endpoint
    web_ips=$(echo "$outputs" | jq -r '.web_instance_public_ips.value[]? // empty' 2>/dev/null || echo "")
    app_ips=$(echo "$outputs" | jq -r '.app_instance_private_ips.value[]? // empty' 2>/dev/null || echo "")
    db_endpoint=$(echo "$outputs" | jq -r '.database_endpoint.value // empty' 2>/dev/null || echo "")
    
    case $format in
        ini)
            build_ini_inventory "$web_ips" "$app_ips" "$db_endpoint"
            ;;
        yaml)
            build_yaml_inventory "$web_ips" "$app_ips" "$db_endpoint"
            ;;
        json)
            build_json_inventory "$web_ips" "$app_ips" "$db_endpoint"
            ;;
    esac
}

build_ini_inventory() {
    local web_ips="$1"
    local app_ips="$2"
    local db_endpoint="$3"
    
    # Generate INI format inventory
    cat << EOF
# Generated Ansible inventory for environment: $ENVIRONMENT
# Generated on: $(date)

[webservers]
EOF
    
    if [ -n "$web_ips" ]; then
        local i=1
        for ip in $web_ips; do
            echo "web-$i ansible_host=$ip ansible_user=ubuntu"
            ((i++))
        done
    fi
    
    echo
    echo "[appservers]"
    
    if [ -n "$app_ips" ]; then
        local i=1
        for ip in $app_ips; do
            echo "app-$i ansible_host=$ip ansible_user=ubuntu"
            ((i++))
        done
    fi
    
    echo
    if [ -n "$db_endpoint" ]; then
        echo "[databases]"
        local db_host
        db_host=$(echo "$db_endpoint" | cut -d: -f1)
        echo "database ansible_host=$db_host"
        echo
    fi
    
    cat << EOF
[all:vars]
environment=$ENVIRONMENT
project_name=iac-solution
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_ssh_common_args=-o StrictHostKeyChecking=no
EOF
}

build_yaml_inventory() {
    local web_ips="$1"
    local app_ips="$2"
    local db_endpoint="$3"
    
    cat << EOF
# Generated Ansible inventory for environment: $ENVIRONMENT
# Generated on: $(date)

all:
  vars:
    environment: $ENVIRONMENT
    project_name: iac-solution
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
    ansible_ssh_common_args: -o StrictHostKeyChecking=no
  children:
EOF
    
    if [ -n "$web_ips" ]; then
        echo "    webservers:"
        echo "      hosts:"
        local i=1
        for ip in $web_ips; do
            cat << EOF
        web-$i:
          ansible_host: $ip
          ansible_user: ubuntu
EOF
            ((i++))
        done
    fi
    
    if [ -n "$app_ips" ]; then
        echo "    appservers:"
        echo "      hosts:"
        local i=1
        for ip in $app_ips; do
            cat << EOF
        app-$i:
          ansible_host: $ip
          ansible_user: ubuntu
EOF
            ((i++))
        done
    fi
    
    if [ -n "$db_endpoint" ]; then
        echo "    databases:"
        echo "      hosts:"
        local db_host
        db_host=$(echo "$db_endpoint" | cut -d: -f1)
        cat << EOF
        database:
          ansible_host: $db_host
EOF
    fi
}

build_json_inventory() {
    local web_ips="$1"
    local app_ips="$2"
    local db_endpoint="$3"
    
    python3 << EOF
import json

inventory = {
    "all": {
        "vars": {
            "environment": "$ENVIRONMENT",
            "project_name": "iac-solution",
            "ansible_ssh_private_key_file": "~/.ssh/id_rsa",
            "ansible_ssh_common_args": "-o StrictHostKeyChecking=no"
        },
        "children": {}
    },
    "_meta": {
        "hostvars": {}
    }
}

# Add web servers
web_ips = "$web_ips".strip().split() if "$web_ips".strip() else []
if web_ips:
    inventory["all"]["children"]["webservers"] = {"hosts": {}}
    for i, ip in enumerate(web_ips, 1):
        host = f"web-{i}"
        inventory["all"]["children"]["webservers"]["hosts"][host] = {}
        inventory["_meta"]["hostvars"][host] = {
            "ansible_host": ip,
            "ansible_user": "ubuntu"
        }

# Add app servers
app_ips = "$app_ips".strip().split() if "$app_ips".strip() else []
if app_ips:
    inventory["all"]["children"]["appservers"] = {"hosts": {}}
    for i, ip in enumerate(app_ips, 1):
        host = f"app-{i}"
        inventory["all"]["children"]["appservers"]["hosts"][host] = {}
        inventory["_meta"]["hostvars"][host] = {
            "ansible_host": ip,
            "ansible_user": "ubuntu"
        }

# Add database
if "$db_endpoint".strip():
    db_host = "$db_endpoint".split(':')[0]
    inventory["all"]["children"]["databases"] = {"hosts": {"database": {}}}
    inventory["_meta"]["hostvars"]["database"] = {
        "ansible_host": db_host
    }

print(json.dumps(inventory, indent=2))
EOF
}

write_inventory_file() {
    local content="$1"
    local format="$2"
    
    # Create inventory directory if it doesn't exist
    mkdir -p "$ANSIBLE_DIR/inventory"
    
    # Determine output file
    local output_file
    case $format in
        ini)
            output_file="$ANSIBLE_DIR/inventory/$ENVIRONMENT.ini"
            ;;
        yaml)
            output_file="$ANSIBLE_DIR/inventory/$ENVIRONMENT.yml"
            ;;
        json)
            output_file="$ANSIBLE_DIR/inventory/$ENVIRONMENT.json"
            ;;
    esac
    
    # Write content to file
    echo "$content" > "$output_file"
    log_success "Inventory written to: $output_file"
    
    # Make dynamic inventory script executable if it exists
    if [ -f "$ANSIBLE_DIR/inventory/dynamic.py" ]; then
        chmod +x "$ANSIBLE_DIR/inventory/dynamic.py"
    fi
}

main() {
    # Parse arguments
    if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
        ENVIRONMENT="$1"
        shift
    fi
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
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
    
    # Validate environment
    case $ENVIRONMENT in
        dev|staging|prod)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
            exit 1
            ;;
    esac
    
    # Validate format
    case $OUTPUT_FORMAT in
        ini|yaml|json)
            ;;
        *)
            log_error "Invalid format: $OUTPUT_FORMAT. Must be one of: ini, yaml, json"
            exit 1
            ;;
    esac
    
    log_info "Generating Ansible inventory for environment: $ENVIRONMENT"
    log_info "Output format: $OUTPUT_FORMAT"
    
    # Check Terraform state
    check_terraform_state
    
    # Get Terraform outputs
    local outputs
    outputs=$(get_terraform_outputs)
    
    if [ "$outputs" = "{}" ]; then
        log_warning "No outputs available, generating minimal inventory"
    fi
    
    # Generate inventory
    local inventory_content
    inventory_content=$(parse_outputs_to_inventory "$outputs" "$OUTPUT_FORMAT")
    
    # Write to file
    write_inventory_file "$inventory_content" "$OUTPUT_FORMAT"
    
    log_success "Inventory generation completed successfully!"
    
    # Show summary if verbose
    if [ "$VERBOSE" = true ]; then
        echo
        log_info "Inventory summary:"
        echo "$inventory_content" | head -20
        if [ $(echo "$inventory_content" | wc -l) -gt 20 ]; then
            echo "... (truncated)"
        fi
    fi
}

# Execute main function
main "$@"
