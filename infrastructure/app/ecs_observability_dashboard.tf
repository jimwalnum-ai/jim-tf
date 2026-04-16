################################################################################
# ECS — Observability Dashboard (active when enable_ecs = true and enable_eks = false)
################################################################################

resource "aws_security_group" "obs_dashboard_alb" {
  count       = local.enable_ecs_web ? 1 : 0
  name        = "${local.ecs_cluster_name}-obs-dash-alb"
  description = "HTTP inbound for observability dashboard ALB"
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

resource "aws_security_group" "obs_dashboard_task" {
  count       = local.enable_ecs_web ? 1 : 0
  name        = "${local.ecs_cluster_name}-obs-dashboard-task"
  description = "Observability dashboard ECS tasks — inbound from ALB only"
  vpc_id      = data.aws_vpc.dev-vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.obs_dashboard_alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_lb" "obs_dashboard" {
  count              = local.enable_ecs_web ? 1 : 0
  name               = "${local.ecs_cluster_name}-obs-dash"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.obs_dashboard_alb[0].id]
  subnets            = local.ecs_public_subnet_ids

  tags = local.tags
}

resource "aws_lb_target_group" "obs_dashboard" {
  count                = local.enable_ecs_web ? 1 : 0
  name                 = "${local.ecs_cluster_name}-obs-dash"
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

resource "aws_lb_listener" "obs_dashboard" {
  count             = local.enable_ecs_web ? 1 : 0
  load_balancer_arn = aws_lb.obs_dashboard[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.obs_dashboard[0].arn
  }
}

################################################################################
# IAM — Observability Dashboard Task Role
################################################################################

resource "aws_iam_role" "ecs_obs_dashboard_task" {
  count              = local.enable_ecs_web ? 1 : 0
  name               = "${local.ecs_cluster_name}-obs-dashboard-task"
  assume_role_policy = templatefile("${path.module}/templates/ecs_task_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy" "ecs_obs_dashboard_task" {
  count = local.enable_ecs_web ? 1 : 0
  name  = "${local.ecs_cluster_name}-obs-dashboard-task"
  role  = aws_iam_role.ecs_obs_dashboard_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchRead"
        Effect   = "Allow"
        Action   = ["cloudwatch:DescribeAlarms", "cloudwatch:GetMetricData"]
        Resource = "*"
      },
      {
        Sid      = "SQSRead"
        Effect   = "Allow"
        Action   = ["sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
        Resource = "*"
      },
      {
        Sid      = "RDSRead"
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances"]
        Resource = "*"
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [local.security_alerts_topic_arn]
      }
    ]
  })
}

################################################################################
# Task Definition + Service
################################################################################

resource "aws_cloudwatch_log_group" "obs_dashboard" {
  count = local.enable_ecs_web ? 1 : 0
  name  = "/ecs/${local.ecs_cluster_name}/obs-dashboard"
  tags  = local.tags
}

resource "aws_ecs_task_definition" "obs_dashboard" {
  count                    = local.enable_ecs_web ? 1 : 0
  family                   = "${local.ecs_cluster_name}-obs-dashboard"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_obs_dashboard_task[0].arn

  container_definitions = jsonencode([{
    name      = "obs-dashboard"
    image     = "${aws_ecr_repository.observability_dashboard[0].repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "AWS_REGION", value = data.aws_region.current.id },
      { name = "CLUSTER_NAME", value = "" },
      { name = "NOMAD_ADDR", value = "http://${try(data.terraform_remote_state.nomad[0].outputs.alb_dns_name, "")}:4646" },
      { name = "SQS_QUEUE_NAMES", value = "SQS_FACTOR_DEV,SQS_FACTOR_RESULT_DEV,${data.aws_sqs_queue.factor_ts.name},${data.aws_sqs_queue.factor_result_ts.name}" },
      { name = "FACTOR_TS_NAMESPACE", value = "" },
      { name = "RDS_INSTANCE_ID", value = aws_db_instance.factor.identifier },
      { name = "SNS_TOPIC_ARN", value = local.security_alerts_topic_arn },
      { name = "NOMAD_IGNORED_DEAD_JOBS", value = "sqs-scaler" },
      { name = "POLL_INTERVAL", value = "10" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.obs_dashboard[0].name
        awslogs-region        = data.aws_region.current.id
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "obs_dashboard" {
  count           = local.enable_ecs_web ? 1 : 0
  name            = "${local.ecs_cluster_name}-obs-dashboard"
  cluster         = aws_ecs_cluster.factor[0].id
  task_definition = aws_ecs_task_definition.obs_dashboard[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.obs_dashboard_task[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.obs_dashboard[0].arn
    container_name   = "obs-dashboard"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.obs_dashboard]
}
