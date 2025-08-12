# Compute Module - EC2 instances, Auto Scaling, Load Balancer
# Manages compute resources for web and application tiers

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch Template for Web Servers
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-${var.environment}-web-"
  description   = "Launch template for web servers"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.web_instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  vpc_security_group_ids = [var.web_security_group_id]

  user_data = base64encode(templatefile("${path.module}/user_data/web_server.sh", {
    environment = var.environment
    project_name = var.project_name
  }))

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-${var.environment}-web"
      Type = "webserver"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.project_name}-${var.environment}-web-volume"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Launch Template for Application Servers
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${var.environment}-app-"
  description   = "Launch template for application servers"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.app_instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  vpc_security_group_ids = [var.app_security_group_id]

  user_data = base64encode(templatefile("${path.module}/user_data/app_server.sh", {
    environment = var.environment
    project_name = var.project_name
  }))

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-${var.environment}-app"
      Type = "appserver"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name               = "${var.project_name}-${var.environment}-alb"
  internal           = var.lb_internal
  load_balancer_type = var.lb_type
  security_groups    = [var.web_security_group_id]
  subnets            = var.lb_internal ? var.private_subnet_ids : var.public_subnet_ids

  enable_deletion_protection = var.environment == "prod" ? true : false
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-alb"
  })
}

# Target Group for Web Servers
resource "aws_lb_target_group" "web" {
  count = var.enable_load_balancer ? 1 : 0

  name     = "${var.project_name}-${var.environment}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-web-tg"
  })
}

# Load Balancer Listener
resource "aws_lb_listener" "web" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }

  tags = var.tags
}

# Auto Scaling Group for Web Servers
resource "aws_autoscaling_group" "web" {
  count = var.enable_auto_scaling ? 1 : 0

  name                = "${var.project_name}-${var.environment}-web-asg"
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = var.enable_load_balancer ? [aws_lb_target_group.web[0].arn] : []
  health_check_type   = var.enable_load_balancer ? "ELB" : "EC2"
  health_check_grace_period = 300

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(var.tags, {
      Name = "${var.project_name}-${var.environment}-web-asg"
    })
    
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for Application Servers
resource "aws_autoscaling_group" "app" {
  count = var.enable_auto_scaling ? 1 : 0

  name                = "${var.project_name}-${var.environment}-app-asg"
  vpc_zone_identifier = var.private_subnet_ids
  health_check_type   = "EC2"
  health_check_grace_period = 300

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(var.tags, {
      Name = "${var.project_name}-${var.environment}-app-asg"
    })
    
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Standalone Web Instances (when Auto Scaling is disabled)
resource "aws_instance" "web" {
  count = var.enable_auto_scaling ? 0 : var.web_instance_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type         = var.web_instance_type
  key_name              = var.key_name != "" ? var.key_name : null
  vpc_security_group_ids = [var.web_security_group_id]
  subnet_id             = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]

  user_data = base64encode(templatefile("${path.module}/user_data/web_server.sh", {
    environment = var.environment
    project_name = var.project_name
  }))

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  monitoring = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-web-${count.index + 1}"
    Type = "webserver"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Standalone Application Instances (when Auto Scaling is disabled)
resource "aws_instance" "app" {
  count = var.enable_auto_scaling ? 0 : var.app_instance_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type         = var.app_instance_type
  key_name              = var.key_name != "" ? var.key_name : null
  vpc_security_group_ids = [var.app_security_group_id]
  subnet_id             = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]

  user_data = base64encode(templatefile("${path.module}/user_data/app_server.sh", {
    environment = var.environment
    project_name = var.project_name
  }))

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  monitoring = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-app-${count.index + 1}"
    Type = "appserver"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "web_scale_up" {
  count = var.enable_auto_scaling ? 1 : 0

  name                   = "${var.project_name}-${var.environment}-web-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.web[0].name
}

resource "aws_autoscaling_policy" "web_scale_down" {
  count = var.enable_auto_scaling ? 1 : 0

  name                   = "${var.project_name}-${var.environment}-web-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.web[0].name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "web_cpu_high" {
  count = var.enable_auto_scaling ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-web-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"

  alarm_actions = [aws_autoscaling_policy.web_scale_up[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web[0].name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "web_cpu_low" {
  count = var.enable_auto_scaling ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-web-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "30"
  alarm_description   = "This metric monitors ec2 cpu utilization"

  alarm_actions = [aws_autoscaling_policy.web_scale_down[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web[0].name
  }

  tags = var.tags
}
