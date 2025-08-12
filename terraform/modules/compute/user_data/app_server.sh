#!/bin/bash
# User data script for application servers

set -e

# Variables passed from Terraform
ENVIRONMENT="${environment}"
PROJECT_NAME="${project_name}"

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting user data script for application server"
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
    software-properties-common \
    build-essential

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Install Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt-get install -y nodejs

# Verify Node.js installation
node --version
npm --version

# Install PM2 globally
npm install -g pm2

# Create application user
useradd -m -s /bin/bash app || true
mkdir -p /home/app/.ssh
chmod 700 /home/app/.ssh
chown -R app:app /home/app

# Create application directories
mkdir -p /opt/iac-solution-app
mkdir -p /var/log/iac-solution-app
chown -R app:app /opt/iac-solution-app
chown -R app:app /var/log/iac-solution-app

# Create basic Node.js application (Ansible will deploy the real app)
cat > /opt/iac-solution-app/app.js << EOF
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
    res.status(200).json({
        status: 'healthy',
        environment: '$ENVIRONMENT',
        project: '$PROJECT_NAME',
        timestamp: new Date().toISOString(),
        uptime: process.uptime()
    });
});

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        message: 'Welcome to $PROJECT_NAME API',
        environment: '$ENVIRONMENT',
        version: '1.0.0',
        timestamp: new Date().toISOString()
    });
});

// Start server
app.listen(port, '0.0.0.0', () => {
    console.log(\`Server running on port \${port}\`);
});

module.exports = app;
EOF

# Create package.json
cat > /opt/iac-solution-app/package.json << EOF
{
  "name": "iac-solution-app",
  "version": "1.0.0",
  "description": "IaC Solution Application",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "dev": "nodemon app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

# Install application dependencies
cd /opt/iac-solution-app
sudo -u app npm install
cd /

# Create PM2 ecosystem file
cat > /opt/iac-solution-app/ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'iac-solution-app',
    script: './app.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: '$ENVIRONMENT',
      PORT: 3000
    },
    log_file: '/var/log/iac-solution-app/combined.log',
    out_file: '/var/log/iac-solution-app/out.log',
    error_file: '/var/log/iac-solution-app/error.log',
    log_date_format: 'YYYY-MM-DD HH:mm Z',
    max_memory_restart: '1G'
  }]
};
EOF

chown -R app:app /opt/iac-solution-app

# Start application with PM2 (as app user)
sudo -u app bash << 'APPUSER_EOF'
cd /opt/iac-solution-app
pm2 start ecosystem.config.js
pm2 startup systemd -u app --hp /home/app
pm2 save
APPUSER_EOF

# Configure firewall
ufw --force enable
ufw allow ssh
ufw allow 3000  # Application port

# Set up CloudWatch agent configuration
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
                        "file_path": "/var/log/iac-solution-app/combined.log",
                        "log_group_name": "$PROJECT_NAME-$ENVIRONMENT-app",
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/var/log/iac-solution-app/error.log",
                        "log_group_name": "$PROJECT_NAME-$ENVIRONMENT-app-errors",
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
hostnamectl set-hostname "$PROJECT_NAME-$ENVIRONMENT-app-$(date +%s)"

# Install Python packages for Ansible
apt-get install -y python3 python3-pip
pip3 install boto3 psycopg2-binary

# Install database client tools
apt-get install -y postgresql-client

# Create application monitoring script
cat > /opt/iac-solution-app/health-check.sh << 'EOF'
#!/bin/bash
# Application health check script

HEALTH_URL="http://localhost:3000/health"
TIMEOUT=5

if curl -s --max-time $TIMEOUT "$HEALTH_URL" | grep -q "healthy"; then
    echo "Application is healthy"
    exit 0
else
    echo "Application health check failed"
    exit 1
fi
EOF

chmod +x /opt/iac-solution-app/health-check.sh
chown app:app /opt/iac-solution-app/health-check.sh

# Set up log rotation
cat > /etc/logrotate.d/iac-solution-app << EOF
/var/log/iac-solution-app/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su app app
}
EOF

# Signal completion
echo "User data script completed successfully" | logger -t user-data
echo "Application server is ready for Ansible configuration"

# Test application
sleep 5
if curl -s http://localhost:3000/health | grep -q "healthy"; then
    echo "Application is running and healthy"
else
    echo "Application may not be running properly"
fi

# Create completion marker
touch /var/log/user-data-completed
chmod 644 /var/log/user-data-completed
