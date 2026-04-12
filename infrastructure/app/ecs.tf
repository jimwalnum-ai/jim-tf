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
  description = "Container image for the factor scripts (set to ECR URL after first build)."
  default     = null
}

variable "ecs_process_cpu" {
  type        = string
  description = "Fargate CPU units for the process task."
  default     = "2048"
}

variable "ecs_process_memory" {
  type        = string
  description = "Fargate memory (MiB) for the process task."
  default     = "4096"
}

variable "ecs_process_desired_count" {
  type        = number
  description = "Desired number of process tasks."
  default     = 1
}

variable "ecs_persist_desired_count" {
  type        = number
  description = "Desired number of persist tasks."
  default     = 1
}

variable "ecs_autoscaling_max" {
  type        = number
  description = "Maximum number of tasks for autoscaling."
  default     = 1
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

variable "web_db_name" {
  type        = string
  description = "Database name for the web service."
  default     = "factors"
}

data "aws_subnets" "public_selected" {
  count = local.enable_ecs ? 1 : 0

  filter {
    name   = "tag:scope"
    values = ["public"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev-vpc.id]
  }
}


locals {
  ecs_cluster_name      = var.ecs_cluster_name != null && var.ecs_cluster_name != "" ? var.ecs_cluster_name : "ecs-factor-${var.env}"
  ecs_image_resolved    = var.ecs_image != null ? var.ecs_image : "${aws_ecr_repository.factor_worker.repository_url}:latest"
  process_script_b64    = base64encode(file("${path.module}/../code/process.py"))
  persist_script_b64    = base64encode(file("${path.module}/../code/persist.py"))
  test_msg_script_b64   = base64encode(file("${path.module}/../code/test_msg.py"))
  ecs_public_subnet_ids = local.enable_ecs ? data.aws_subnets.public_selected[0].ids : []
  decode_script = trimspace(<<-EOT
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/run.py").write_bytes(base64.b64decode(os.environ["SCRIPT_B64"]))
    PY
  EOT
  )
  process_command = trimspace(<<-EOT
    set -e
    ${local.decode_script}
    while true; do python /app/run.py || true; sleep 5; done
  EOT
  )
  persist_command = trimspace(<<-EOT
    set -e
    ${local.decode_script}
    while true; do python /app/run.py || true; sleep 5; done
  EOT
  )
  test_msg_command = trimspace(<<-EOT
    set -e
    ${local.decode_script}
    python /app/run.py
  EOT
  )
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
  vpc_id      = data.aws_vpc.dev-vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  cpu                      = var.ecs_process_cpu
  memory                   = var.ecs_process_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  container_definitions = jsonencode([
    {
      name       = "process"
      image      = local.ecs_image_resolved
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.process_command]
      environment = [
        {
          name  = "SCRIPT_B64"
          value = local.process_script_b64
        }
      ]
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
      name       = "persist"
      image      = local.ecs_image_resolved
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.persist_command]
      environment = [
        {
          name  = "SCRIPT_B64"
          value = local.persist_script_b64
        }
      ]
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
      name       = "test-msg"
      image      = local.ecs_image_resolved
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.test_msg_command]
      environment = [
        {
          name  = "SCRIPT_B64"
          value = local.test_msg_script_b64
        }
      ]
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
  desired_count   = var.ecs_process_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks[0].id]
    assign_public_ip = var.ecs_assign_public_ip
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "persist" {
  count           = local.enable_ecs ? 1 : 0
  name            = "${local.ecs_cluster_name}-persist"
  cluster         = aws_ecs_cluster.factor[0].id
  task_definition = aws_ecs_task_definition.persist[0].arn
  desired_count   = var.ecs_persist_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_public_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks[0].id]
    assign_public_ip = var.ecs_assign_public_ip
  }

  lifecycle {
    ignore_changes = [desired_count]
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

################################################################################
# Autoscaling — scale process and persist on SQS queue depth
################################################################################

resource "aws_appautoscaling_target" "process" {
  count              = local.enable_ecs ? 1 : 0
  max_capacity       = var.ecs_autoscaling_max
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.factor[0].name}/${aws_ecs_service.process[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "process_scale_up" {
  count              = local.enable_ecs ? 1 : 0
  name               = "${local.ecs_cluster_name}-process-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.process[0].resource_id
  scalable_dimension = aws_appautoscaling_target.process[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.process[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = 1
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 500
    }
    step_adjustment {
      scaling_adjustment          = 2
      metric_interval_lower_bound = 500
    }
  }
}

resource "aws_appautoscaling_policy" "process_scale_down" {
  count              = local.enable_ecs ? 1 : 0
  name               = "${local.ecs_cluster_name}-process-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.process[0].resource_id
  scalable_dimension = aws_appautoscaling_target.process[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.process[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = -1
      metric_interval_upper_bound = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "process_queue_high" {
  count               = local.enable_ecs ? 1 : 0
  alarm_name          = "${local.ecs_cluster_name}-factor-queue-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 100
  alarm_actions       = [aws_appautoscaling_policy.process_scale_up[0].arn]
  dimensions = {
    QueueName = local.factor_queue_name
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "process_queue_low" {
  count               = local.enable_ecs ? 1 : 0
  alarm_name          = "${local.ecs_cluster_name}-factor-queue-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 10
  alarm_actions       = [aws_appautoscaling_policy.process_scale_down[0].arn]
  dimensions = {
    QueueName = local.factor_queue_name
  }
  tags = local.tags
}

resource "aws_appautoscaling_target" "persist" {
  count              = local.enable_ecs ? 1 : 0
  max_capacity       = var.ecs_autoscaling_max
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.factor[0].name}/${aws_ecs_service.persist[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "persist_scale_up" {
  count              = local.enable_ecs ? 1 : 0
  name               = "${local.ecs_cluster_name}-persist-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.persist[0].resource_id
  scalable_dimension = aws_appautoscaling_target.persist[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.persist[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = 1
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 500
    }
    step_adjustment {
      scaling_adjustment          = 2
      metric_interval_lower_bound = 500
    }
  }
}

resource "aws_appautoscaling_policy" "persist_scale_down" {
  count              = local.enable_ecs ? 1 : 0
  name               = "${local.ecs_cluster_name}-persist-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.persist[0].resource_id
  scalable_dimension = aws_appautoscaling_target.persist[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.persist[0].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = -1
      metric_interval_upper_bound = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "persist_queue_high" {
  count               = local.enable_ecs ? 1 : 0
  alarm_name          = "${local.ecs_cluster_name}-result-queue-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 100
  alarm_actions       = [aws_appautoscaling_policy.persist_scale_up[0].arn]
  dimensions = {
    QueueName = local.factor_result_queue_name
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "persist_queue_low" {
  count               = local.enable_ecs ? 1 : 0
  alarm_name          = "${local.ecs_cluster_name}-result-queue-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 10
  alarm_actions       = [aws_appautoscaling_policy.persist_scale_down[0].arn]
  dimensions = {
    QueueName = local.factor_result_queue_name
  }
  tags = local.tags
}
