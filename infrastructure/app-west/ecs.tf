variable "env" {
  type        = string
  description = "Environment name (e.g. dev, prd)."
  default     = "dev"
}

variable "ecs_cluster_name" {
  type        = string
  description = "Optional ECS cluster name override."
  default     = null
}

variable "ecs_image" {
  type        = string
  description = "Override container image for all factor tasks (leave null to use per-task ECR repos)."
  default     = null
}

variable "ecs_assign_public_ip" {
  type        = bool
  description = "Assign public IPs to ECS tasks."
  default     = true
}

variable "ecs_task_cpu" {
  type        = string
  description = "Fargate task CPU units."
  default     = "256"
}

variable "ecs_task_memory" {
  type        = string
  description = "Fargate task memory in MiB."
  default     = "512"
}

variable "ecs_test_msg_schedule" {
  type        = string
  description = "Schedule expression for test_msg task."
  default     = "rate(30 minutes)"
}

data "aws_subnets" "public_selected" {
  count = local.enable_ecs ? 1 : 0

  filter {
    name   = "tag:scope"
    values = ["public"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev-vpc-west.id]
  }
}

locals {
  ecs_cluster_name      = var.ecs_cluster_name != null && var.ecs_cluster_name != "" ? var.ecs_cluster_name : "ecs-factor-west-${var.env}"
  ecs_public_subnet_ids = local.enable_ecs ? data.aws_subnets.public_selected[0].ids : []
  factor_process_image  = var.ecs_image != null ? var.ecs_image : "${aws_ecr_repository.factor_process.repository_url}:latest"
  factor_persist_image  = var.ecs_image != null ? var.ecs_image : "${aws_ecr_repository.factor_persist.repository_url}:latest"
  factor_test_msg_image = var.ecs_image != null ? var.ecs_image : "${aws_ecr_repository.factor_test_msg.repository_url}:latest"
}

resource "aws_ecs_cluster" "factor" {
  count = local.enable_ecs ? 1 : 0
  name  = local.ecs_cluster_name
  tags  = local.tags
}

resource "aws_security_group" "ecs_tasks" {
  count       = local.enable_ecs ? 1 : 0
  name        = "${local.ecs_cluster_name}-tasks"
  description = "ECS tasks for factor workloads"
  vpc_id      = data.aws_vpc.dev-vpc-west.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #trivy:ignore:AVD-AWS-0104
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "process" {
  count = local.enable_ecs ? 1 : 0
  name  = "/ecs/${local.ecs_cluster_name}/process"
  tags  = local.tags
}

resource "aws_cloudwatch_log_group" "persist" {
  count = local.enable_ecs ? 1 : 0
  name  = "/ecs/${local.ecs_cluster_name}/persist"
  tags  = local.tags
}

resource "aws_cloudwatch_log_group" "test_msg" {
  count = local.enable_ecs ? 1 : 0
  name  = "/ecs/${local.ecs_cluster_name}/test-msg"
  tags  = local.tags
}

resource "aws_ecs_task_definition" "process" {
  count                    = local.enable_ecs ? 1 : 0
  family                   = "${local.ecs_cluster_name}-process"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  container_definitions = jsonencode([
    {
      name      = "process"
      image     = local.factor_process_image
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.process[0].name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "persist" {
  count                    = local.enable_ecs ? 1 : 0
  family                   = "${local.ecs_cluster_name}-persist"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  container_definitions = jsonencode([
    {
      name      = "persist"
      image     = local.factor_persist_image
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.persist[0].name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "test_msg" {
  count                    = local.enable_ecs ? 1 : 0
  family                   = "${local.ecs_cluster_name}-test-msg"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  container_definitions = jsonencode([
    {
      name      = "test-msg"
      image     = local.factor_test_msg_image
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.test_msg[0].name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "process" {
  count           = local.enable_ecs ? 1 : 0
  name            = "${local.ecs_cluster_name}-process"
  cluster         = aws_ecs_cluster.factor[0].id
  task_definition = aws_ecs_task_definition.process[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks[0].id]
    assign_public_ip = var.ecs_assign_public_ip
  }
}

resource "aws_ecs_service" "persist" {
  count           = local.enable_ecs ? 1 : 0
  name            = "${local.ecs_cluster_name}-persist"
  cluster         = aws_ecs_cluster.factor[0].id
  task_definition = aws_ecs_task_definition.persist[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks[0].id]
    assign_public_ip = var.ecs_assign_public_ip
  }
}

resource "aws_ecs_service" "test_msg" {
  count           = local.enable_ecs ? 1 : 0
  name            = "${local.ecs_cluster_name}-test-msg"
  cluster         = aws_ecs_cluster.factor[0].id
  task_definition = aws_ecs_task_definition.test_msg[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks[0].id]
    assign_public_ip = var.ecs_assign_public_ip
  }
}

resource "aws_cloudwatch_event_rule" "test_msg" {
  count               = local.enable_ecs ? 1 : 0
  name                = "${local.ecs_cluster_name}-test-msg"
  schedule_expression = var.ecs_test_msg_schedule
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "test_msg" {
  count     = local.enable_ecs ? 1 : 0
  rule      = aws_cloudwatch_event_rule.test_msg[0].name
  target_id = "${local.ecs_cluster_name}-test-msg"
  arn       = aws_ecs_cluster.factor[0].arn
  role_arn  = aws_iam_role.ecs_events[0].arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.test_msg[0].arn
    task_count          = 1
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = local.ecs_public_subnet_ids
      security_groups  = [aws_security_group.ecs_tasks[0].id]
      assign_public_ip = var.ecs_assign_public_ip
    }
  }
}
