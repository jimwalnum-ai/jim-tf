################################################################################
# ECS — Security Dashboard (active when enable_ecs = true and enable_eks = false)
################################################################################

resource "aws_security_group" "sec_dashboard_alb" {
  count       = local.enable_ecs_web ? 1 : 0
  name        = "${local.ecs_cluster_name}-sec-dash-alb"
  description = "HTTP inbound for security dashboard ALB"
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
    cidr_blocks = ["0.0.0.0/0"] #trivy:ignore:AVD-AWS-0104
  }

  tags = local.tags
}

resource "aws_security_group" "sec_dashboard_task" {
  count       = local.enable_ecs_web ? 1 : 0
  name        = "${local.ecs_cluster_name}-sec-dashboard-task"
  description = "Security dashboard ECS tasks inbound from ALB only"
  vpc_id      = data.aws_vpc.dev-vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.sec_dashboard_alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #trivy:ignore:AVD-AWS-0104
  }

  tags = local.tags
}

resource "aws_lb" "security_dashboard" {
  count                      = local.enable_ecs_web ? 1 : 0
  name                       = "${local.ecs_cluster_name}-sec-dash"
  internal                   = false
  load_balancer_type         = "application"
  drop_invalid_header_fields = true
  security_groups            = [aws_security_group.sec_dashboard_alb[0].id]
  subnets                    = local.ecs_public_subnet_ids

  tags = local.tags
}

resource "aws_lb_target_group" "security_dashboard" {
  count                = local.enable_ecs_web ? 1 : 0
  name                 = "${local.ecs_cluster_name}-sec-dash"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.dev-vpc.id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    path                = "/health"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = local.tags
}

#trivy:ignore:AVD-AWS-0054
resource "aws_lb_listener" "security_dashboard" {
  count             = local.enable_ecs_web ? 1 : 0
  load_balancer_arn = aws_lb.security_dashboard[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.security_dashboard[0].arn
  }
}

################################################################################
# IAM — Security Dashboard Task Role
################################################################################

resource "aws_iam_role" "ecs_sec_dashboard_task" {
  count              = local.enable_ecs_web ? 1 : 0
  name               = "${local.ecs_cluster_name}-sec-dashboard-task"
  assume_role_policy = templatefile("${path.module}/templates/ecs_task_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy" "ecs_sec_dashboard_task" {
  count = local.enable_ecs_web ? 1 : 0
  name  = "${local.ecs_cluster_name}-sec-dashboard-task"
  role  = aws_iam_role.ecs_sec_dashboard_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "S3ReadReports"
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        module.hubble_logs_bucket[0].bucket_arn,
        "${module.hubble_logs_bucket[0].bucket_arn}/*",
      ]
    }]
  })
}

################################################################################
# Task Definition + Service
################################################################################

resource "aws_cloudwatch_log_group" "sec_dashboard" {
  count = local.enable_ecs_web ? 1 : 0
  name  = "/ecs/${local.ecs_cluster_name}/sec-dashboard"
  tags  = local.tags
}

resource "aws_ecs_task_definition" "security_dashboard" {
  count                    = local.enable_ecs_web ? 1 : 0
  family                   = "${local.ecs_cluster_name}-sec-dashboard"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_sec_dashboard_task[0].arn

  container_definitions = jsonencode([{
    name      = "sec-dashboard"
    image     = "${aws_ecr_repository.security_dashboard.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "S3_BUCKET", value = module.hubble_logs_bucket[0].bucket_name },
      { name = "REPORTS_PREFIX", value = "security-reports/" },
      { name = "AWS_REGION", value = data.aws_region.current.id },
      { name = "CLUSTER_NAME", value = "" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.sec_dashboard[0].name
        awslogs-region        = data.aws_region.current.id
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "security_dashboard" {
  count           = local.enable_ecs_web ? 1 : 0
  name            = "${local.ecs_cluster_name}-sec-dashboard"
  cluster         = aws_ecs_cluster.factor[0].id
  task_definition = aws_ecs_task_definition.security_dashboard[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.sec_dashboard_task[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.security_dashboard[0].arn
    container_name   = "sec-dashboard"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.security_dashboard]
}
