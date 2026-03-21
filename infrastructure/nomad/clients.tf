resource "aws_launch_template" "client" {
  name_prefix   = "${local.name_prefix}-client-"
  image_id      = data.aws_ami.al2023_arm.id
  instance_type = var.client_instance_type
  key_name      = aws_key_pair.nomad.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.nomad_node.name
  }

  vpc_security_group_ids = [aws_security_group.nomad_cluster.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/templates/client_userdata.sh.tpl", {
    nomad_version       = var.nomad_version
    consul_version      = var.consul_version
    cni_plugins_version = var.cni_plugins_version
    datacenter          = "dc1"
    region              = "us-east-1"
    cpu_total_compute   = var.client_cpu_total_compute
    cluster_tag_key     = "nomad-cluster"
    cluster_tag_value   = local.name_prefix
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-client" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "clients" {
  name                = "${local.name_prefix}-clients"
  min_size            = var.client_min_count
  max_size            = var.client_max_count
  desired_capacity    = var.client_min_count
  vpc_zone_identifier = data.aws_subnets.public.ids

  launch_template {
    id      = aws_launch_template.client.id
    version = aws_launch_template.client.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-client"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
