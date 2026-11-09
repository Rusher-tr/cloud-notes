# ----------------------------------------------------------------------------
# Compute: Auto Scaling Group of EC2 container hosts in the PRIVATE app subnets.
# Each host runs the web (Nginx) and app (Flask) containers via docker compose.
# ----------------------------------------------------------------------------

# Always the latest Amazon Linux 2023 AMI (patched base OS on every new launch).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-host-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  # IMDSv2 only. Hop limit 2 lets containers reach instance-role credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region          = var.aws_region
    registry        = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    web_repo        = aws_ecr_repository.repo["web"].repository_url
    app_repo        = aws_ecr_repository.repo["app"].repository_url
    db_host         = aws_db_instance.main.address
    db_port         = aws_db_instance.main.port
    db_name         = aws_db_instance.main.db_name
    db_secret_arn   = local.db_secret_arn
    log_group       = aws_cloudwatch_log_group.containers.name
    compose_version = var.docker_compose_version
    compose_file    = file("${path.module}/../docker-compose.yml")
    deploy_script   = file("${path.module}/templates/deploy.sh")
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-host" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.name}-host-root" }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${local.name}-asg"
  vpc_zone_identifier = aws_subnet.app[*].id # spread across both AZs
  min_size            = var.asg_min_size
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size

  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB" # replace instances the ALB marks unhealthy, not just dead VMs
  health_check_grace_period = 600   # first boot installs Docker and waits for the first image push

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # Changing the launch template rolls instances one by one, keeping >= 50% serving.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  enabled_metrics     = ["GroupInServiceInstances", "GroupDesiredCapacity", "GroupMinSize", "GroupMaxSize"]
  metrics_granularity = "1Minute"

  tag {
    key                 = "Name"
    value               = "${local.name}-host"
    propagate_at_launch = true
  }

  # The pipeline may only send deploy commands to instances carrying this tag.
  tag {
    key                 = "DeployGroup"
    value               = local.name
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity] # owned by the scaling policy after creation
  }
}

# Elasticity: add hosts when average CPU > target, remove them when it drops.
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${local.name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_percent
  }
}
