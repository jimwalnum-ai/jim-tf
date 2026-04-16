resource "aws_security_group" "alb" {
  count       = local.enabled
  name        = "${local.name_prefix}-alb"
  description = "ALB for Nomad and Consul UIs"
  vpc_id      = data.aws_vpc.dev.id

  ingress {
    description = "Nomad UI from admin"
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = [local.home_ip]
  }

  ingress {
    description = "Consul UI from admin"
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = [local.home_ip]
  }

  egress {
    description = "Health checks and forwarding to targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.dev.cidr_block]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

resource "aws_lb" "nomad" {
  count                      = local.enabled
  name                       = "${local.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  drop_invalid_header_fields = true
  security_groups            = [aws_security_group.alb[0].id]
  subnets                    = data.aws_subnets.public.ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

# ── Nomad target group + listener ────────────────────────────────────

resource "aws_lb_target_group" "nomad" {
  count    = local.enabled
  name     = "${local.name_prefix}-nomad"
  port     = 4646
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.dev.id

  health_check {
    path                = "/v1/agent/health"
    port                = "4646"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "nomad" {
  count            = local.server_actual_count
  target_group_arn = aws_lb_target_group.nomad[0].arn
  target_id        = aws_instance.server[count.index].id
  port             = 4646
}

#trivy:ignore:AVD-AWS-0054
resource "aws_lb_listener" "nomad" {
  count             = local.enabled
  load_balancer_arn = aws_lb.nomad[0].arn
  port              = 4646
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad[0].arn
  }

  tags = local.tags
}

# ── Consul target group + listener ───────────────────────────────────

resource "aws_lb_target_group" "consul" {
  count    = local.enabled
  name     = "${local.name_prefix}-consul"
  port     = 8500
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.dev.id

  health_check {
    path                = "/v1/status/leader"
    port                = "8500"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "consul" {
  count            = local.server_actual_count
  target_group_arn = aws_lb_target_group.consul[0].arn
  target_id        = aws_instance.server[count.index].id
  port             = 8500
}

#trivy:ignore:AVD-AWS-0054
resource "aws_lb_listener" "consul" {
  count             = local.enabled
  load_balancer_arn = aws_lb.nomad[0].arn
  port              = 8500
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul[0].arn
  }

  tags = local.tags
}
