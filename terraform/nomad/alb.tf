resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "ALB for Nomad and Consul UIs"
  vpc_id      = data.aws_vpc.dev.id

  ingress {
    description = "All inbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

resource "aws_lb" "nomad" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

# ── Nomad target group + listener ────────────────────────────────────

resource "aws_lb_target_group" "nomad" {
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
  count            = var.server_count
  target_group_arn = aws_lb_target_group.nomad.arn
  target_id        = aws_instance.server[count.index].id
  port             = 4646
}

resource "aws_lb_listener" "nomad" {
  load_balancer_arn = aws_lb.nomad.arn
  port              = 4646
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad.arn
  }

  tags = local.tags
}

# ── Consul target group + listener ───────────────────────────────────

resource "aws_lb_target_group" "consul" {
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
  count            = var.server_count
  target_group_arn = aws_lb_target_group.consul.arn
  target_id        = aws_instance.server[count.index].id
  port             = 8500
}

resource "aws_lb_listener" "consul" {
  load_balancer_arn = aws_lb.nomad.arn
  port              = 8500
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul.arn
  }

  tags = local.tags
}
