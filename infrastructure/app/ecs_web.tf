################################################################################
# ECS — Flask App (active when enable_ecs = true and enable_eks = false)
################################################################################

resource "aws_security_group" "web_alb" {
  count       = local.enable_ecs_web ? 1 : 0
  name        = "${local.ecs_cluster_name}-web-alb"
  description = "HTTP inbound for Flask app ALB"
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

resource "aws_security_group" "flask_app_task" {
  count       = local.enable_ecs_web ? 1 : 0
  name        = "${local.ecs_cluster_name}-flask-app-task"
  description = "Flask app ECS tasks inbound from ALB only"
  vpc_id      = data.aws_vpc.dev-vpc.id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.web_alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_lb" "flask_app" {
  count              = local.enable_ecs_web ? 1 : 0
  name               = "${local.ecs_cluster_name}-flask-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_alb[0].id]
  subnets            = local.ecs_public_subnet_ids

  tags = local.tags
}

resource "aws_lb_target_group" "flask_app" {
  count                = local.enable_ecs_web ? 1 : 0
  name                 = "${local.ecs_cluster_name}-flask-app"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.dev-vpc.id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    path                = "/health"
    port                = "8000"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = local.tags
}

resource "aws_lb_listener" "flask_app" {
  count             = local.enable_ecs_web ? 1 : 0
  load_balancer_arn = aws_lb.flask_app[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_app[0].arn
  }
}

resource "aws_cloudwatch_log_group" "flask_app" {
  count = local.enable_ecs_web ? 1 : 0
  name  = "/ecs/${local.ecs_cluster_name}/flask-app"
  tags  = local.tags
}

resource "aws_ecs_task_definition" "flask_app" {
  count                    = local.enable_ecs_web ? 1 : 0
  family                   = "${local.ecs_cluster_name}-flask-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn

  container_definitions = jsonencode([{
    name      = "flask-app"
    image     = "${aws_ecr_repository.flask_app.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]
    environment = [
      { name = "FACTOR_DB_HOST", value = aws_db_instance.factor.address },
      { name = "FACTOR_DB_PORT", value = tostring(aws_db_instance.factor.port) },
      { name = "FACTOR_DB_NAME", value = var.web_db_name },
      { name = "FACTOR_DB_USER", value = aws_db_instance.factor.username },
    ]
    secrets = [{
      name      = "FACTOR_DB_PASSWORD"
      valueFrom = "${aws_secretsmanager_secret.cs_rds_credentials.arn}:password::"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.flask_app[0].name
        awslogs-region        = data.aws_region.current.id
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "flask_app" {
  count           = local.enable_ecs_web ? 1 : 0
  name            = "${local.ecs_cluster_name}-flask-app"
  cluster         = aws_ecs_cluster.factor[0].id
  task_definition = aws_ecs_task_definition.flask_app[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.flask_app_task[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.flask_app[0].arn
    container_name   = "flask-app"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.flask_app]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
