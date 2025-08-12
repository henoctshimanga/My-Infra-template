#!/usr/bin/env python3
"""
Dynamic inventory script for AWS infrastructure
Reads Terraform outputs and generates Ansible inventory
"""

import json
import sys
import os
import subprocess
import argparse
from typing import Dict, List, Any

class TerraformInventory:
    def __init__(self):
        self.inventory = {
            '_meta': {
                'hostvars': {}
            }
        }
        
    def get_terraform_output(self, terraform_dir: str = "./terraform") -> Dict[str, Any]:
        """Get Terraform outputs as JSON"""
        try:
            cmd = ["terraform", "output", "-json"]
            result = subprocess.run(
                cmd, 
                cwd=terraform_dir, 
                capture_output=True, 
                text=True, 
                check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"Error getting Terraform outputs: {e}", file=sys.stderr)
            return {}
        except json.JSONDecodeError as e:
            print(f"Error parsing Terraform output JSON: {e}", file=sys.stderr)
            return {}
    
    def parse_ansible_inventory(self, tf_outputs: Dict[str, Any]) -> None:
        """Parse Terraform outputs into Ansible inventory format"""
        
        # Get ansible inventory from Terraform outputs
        if 'ansible_inventory' in tf_outputs:
            inventory_data = tf_outputs['ansible_inventory']['value']
            if isinstance(inventory_data, str):
                inventory_data = json.loads(inventory_data)
            
            # Extract groups and hosts
            if 'all' in inventory_data and 'children' in inventory_data['all']:
                children = inventory_data['all']['children']
                
                # Process webservers
                if 'webservers' in children and 'hosts' in children['webservers']:
                    self.inventory['webservers'] = {
                        'hosts': list(children['webservers']['hosts'].keys()),
                        'vars': {
                            'ansible_user': 'ubuntu',
                            'ansible_ssh_private_key_file': '~/.ssh/id_rsa',
                            'server_type': 'webserver'
                        }
                    }
                    
                    # Add host vars
                    for host, vars in children['webservers']['hosts'].items():
                        self.inventory['_meta']['hostvars'][host] = vars
                
                # Process appservers
                if 'appservers' in children and 'hosts' in children['appservers']:
                    self.inventory['appservers'] = {
                        'hosts': list(children['appservers']['hosts'].keys()),
                        'vars': {
                            'ansible_user': 'ubuntu',
                            'ansible_ssh_private_key_file': '~/.ssh/id_rsa',
                            'server_type': 'appserver'
                        }
                    }
                    
                    # Add host vars
                    for host, vars in children['appservers']['hosts'].items():
                        self.inventory['_meta']['hostvars'][host] = vars
                
                # Process databases
                if 'databases' in children and 'hosts' in children['databases']:
                    self.inventory['databases'] = {
                        'hosts': list(children['databases']['hosts'].keys()),
                        'vars': {
                            'server_type': 'database'
                        }
                    }
                    
                    # Add host vars
                    for host, vars in children['databases']['hosts'].items():
                        self.inventory['_meta']['hostvars'][host] = vars
                
                # Add global vars
                if 'vars' in inventory_data['all']:
                    self.inventory['all'] = {
                        'vars': inventory_data['all']['vars']
                    }
        
        # Fallback: try to extract from individual outputs
        else:
            self._parse_individual_outputs(tf_outputs)
    
    def _parse_individual_outputs(self, tf_outputs: Dict[str, Any]) -> None:
        """Parse individual Terraform outputs when ansible_inventory is not available"""
        
        # Extract web servers
        web_ips = tf_outputs.get('web_instance_public_ips', {}).get('value', [])
        if web_ips:
            self.inventory['webservers'] = {
                'hosts': [f"web-{i+1}" for i in range(len(web_ips))],
                'vars': {
                    'ansible_user': 'ubuntu',
                    'server_type': 'webserver'
                }
            }
            
            for i, ip in enumerate(web_ips):
                host = f"web-{i+1}"
                self.inventory['_meta']['hostvars'][host] = {
                    'ansible_host': ip,
                    'ansible_user': 'ubuntu'
                }
        
        # Extract app servers
        app_ips = tf_outputs.get('app_instance_private_ips', {}).get('value', [])
        if app_ips:
            self.inventory['appservers'] = {
                'hosts': [f"app-{i+1}" for i in range(len(app_ips))],
                'vars': {
                    'ansible_user': 'ubuntu',
                    'server_type': 'appserver'
                }
            }
            
            for i, ip in enumerate(app_ips):
                host = f"app-{i+1}"
                self.inventory['_meta']['hostvars'][host] = {
                    'ansible_host': ip,
                    'ansible_user': 'ubuntu'
                }
        
        # Extract database info
        db_endpoint = tf_outputs.get('database_endpoint', {}).get('value')
        if db_endpoint:
            self.inventory['databases'] = {
                'hosts': ['database'],
                'vars': {
                    'server_type': 'database'
                }
            }
            
            self.inventory['_meta']['hostvars']['database'] = {
                'ansible_host': db_endpoint.split(':')[0],
                'db_engine': tf_outputs.get('database_engine', {}).get('value', 'postgres'),
                'db_port': tf_outputs.get('database_port', {}).get('value', 5432)
            }
        
        # Add common vars
        self.inventory['all'] = {
            'vars': {
                'environment': tf_outputs.get('infrastructure_info', {}).get('value', {}).get('environment', 'unknown'),
                'project_name': 'iac-solution',
                'aws_region': tf_outputs.get('infrastructure_info', {}).get('value', {}).get('region', 'us-west-2')
            }
        }
    
    def get_inventory(self) -> Dict[str, Any]:
        """Get the complete inventory"""
        terraform_dir = os.environ.get('TERRAFORM_DIR', './terraform')
        tf_outputs = self.get_terraform_output(terraform_dir)
        
        if tf_outputs:
            self.parse_ansible_inventory(tf_outputs)
        else:
            # Return empty inventory if no Terraform outputs
            self.inventory = {
                'all': {
                    'hosts': [],
                    'vars': {}
                },
                '_meta': {
                    'hostvars': {}
                }
            }
        
        return self.inventory
    
    def get_host(self, hostname: str) -> Dict[str, Any]:
        """Get variables for a specific host"""
        inventory = self.get_inventory()
        return inventory.get('_meta', {}).get('hostvars', {}).get(hostname, {})

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Dynamic inventory for Terraform-managed infrastructure')
    parser.add_argument('--list', action='store_true', help='List all hosts')
    parser.add_argument('--host', help='Get variables for specific host')
    args = parser.parse_args()
    
    inventory = TerraformInventory()
    
    if args.list:
        print(json.dumps(inventory.get_inventory(), indent=2))
    elif args.host:
        print(json.dumps(inventory.get_host(args.host), indent=2))
    else:
        parser.print_help()

if __name__ == '__main__':
    main()

