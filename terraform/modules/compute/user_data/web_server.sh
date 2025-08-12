#!/bin/bash
# User data script for web servers

set -e

# Variables passed from Terraform
ENVIRONMENT="${environment}"
PROJECT_NAME="${project_name}"

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting user data script for web server"
echo "Environment: $ENVIRONMENT"
echo "Project: $PROJECT_NAME"

# Update system
apt-get update
apt-get upgrade -y

# Install basic packages
apt-get install -y \
    curl \
    wget \
    unzip \
    htop \
    vim \
    git \
    awscli \
    python3-pip \
    software-properties-common

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Install and configure nginx (basic setup, Ansible will handle detailed config)
apt-get install -y nginx

# Create basic nginx configuration
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name _;
    server_tokens off;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

server {
    listen 8080;
    server_name _;
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        deny all;
    }
}
EOF

# Create a simple index page
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $PROJECT_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { color: #333; }
        .info { background: #f4f4f4; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1 class="header">Welcome to $PROJECT_NAME</h1>
    <div class="info">
        <h2>Server Information</h2>
        <p><strong>Environment:</strong> $ENVIRONMENT</p>
        <p><strong>Server Type:</strong> Web Server</p>
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>Date:</strong> $(date)</p>
        <p><strong>Status:</strong> Ready for configuration by Ansible</p>
    </div>
    
    <h2>Health Check</h2>
    <p>Health check endpoint: <a href="/health">/health</a></p>
</body>
</html>
EOF

# Test nginx configuration and start
nginx -t
systemctl enable nginx
systemctl start nginx

# Configure basic firewall
ufw --force enable
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 8080

# Set up CloudWatch agent basic configuration
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "$PROJECT_NAME/$ENVIRONMENT",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "$PROJECT_NAME-$ENVIRONMENT-nginx-access",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/nginx/error.log",
                        "log_group_name": "$PROJECT_NAME-$ENVIRONMENT-nginx-error",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Create ansible user for configuration
useradd -m -s /bin/bash ansible || true
mkdir -p /home/ansible/.ssh
chmod 700 /home/ansible/.ssh

# Add ansible user to sudoers
echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
chmod 440 /etc/sudoers.d/ansible

# Set hostname
hostnamectl set-hostname "$PROJECT_NAME-$ENVIRONMENT-web-$(date +%s)"

# Install Python for Ansible
apt-get install -y python3 python3-pip
pip3 install boto3

# Signal completion
echo "User data script completed successfully" | logger -t user-data
echo "Web server is ready for Ansible configuration"

# Create completion marker
touch /var/log/user-data-completed
chmod 644 /var/log/user-data-completed
