data "terraform_remote_state" "basics" {
  backend = "s3"

  config = {
    bucket               = "csx7-use1-terraform-state"
    key                  = "basics/state.tfstate"
    region               = "us-east-1"
    workspace_key_prefix = "basics"
  }
}

resource "aws_security_group" "alb_web" {
  name        = "${local.ecs_cluster_name}-alb-web"
  description = "ALB for web service"
  vpc_id      = data.aws_vpc.dev-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "web_tasks" {
  name        = "${local.ecs_cluster_name}-web-tasks"
  description = "ECS tasks for web service"
  vpc_id      = data.aws_vpc.dev-vpc.id

  ingress {
    description     = "From ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_lb" "web" {
  name               = "${local.ecs_cluster_name}-web"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.public_selected.ids
  security_groups    = [aws_security_group.alb_web.id]
  tags               = local.tags
}

resource "aws_lb_target_group" "web" {
  name        = "${local.ecs_cluster_name}-web"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.dev-vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }

  tags = local.tags
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_route53_record" "web" {
  zone_id = data.terraform_remote_state.basics.outputs.public_zone_id
  name    = "web.crimsonscallion.com"
  type    = "A"

  alias {
    name                   = aws_lb.web.dns_name
    zone_id                = aws_lb.web.zone_id
    evaluate_target_health = true
  }
}
