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
  description = "Container image to run the factor scripts."
  default     = "python:3.11-slim"
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
  ecs_cluster_name        = var.ecs_cluster_name != null && var.ecs_cluster_name != "" ? var.ecs_cluster_name : "ecs-factor-${var.env}"
  ecs_pip_install_command = "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 \"urllib3<2.0\" psycopg2-binary"
  process_script_b64      = base64encode(file("${path.module}/../code/process.py"))
  persist_script_b64      = base64encode(file("${path.module}/../code/persist.py"))
  test_msg_script_b64     = base64encode(file("${path.module}/../code/test_msg.py"))
  web_server_script_b64   = base64encode(file("${path.module}/../web/server.py"))
  web_index_b64           = base64encode(file("${path.module}/../web/index.html"))
  process_command = trimspace(<<-EOT
    set -e
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/process.py").write_bytes(base64.b64decode(os.environ["SCRIPT_B64"]))
    PY
    ${local.ecs_pip_install_command}
    while true; do python /app/process.py || true; sleep 30; done
  EOT
  )
  persist_command = trimspace(<<-EOT
    set -e
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/persist.py").write_bytes(base64.b64decode(os.environ["SCRIPT_B64"]))
    PY
    ${local.ecs_pip_install_command}
    while true; do python /app/persist.py || true; sleep 30; done
  EOT
  )
  test_msg_command = trimspace(<<-EOT
    set -e
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/test_msg.py").write_bytes(base64.b64decode(os.environ["SCRIPT_B64"]))
    PY
    ${local.ecs_pip_install_command}
    python /app/test_msg.py
  EOT
  )
  web_command = trimspace(<<-EOT
    set -e
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/server.py").write_bytes(base64.b64decode(os.environ["SERVER_B64"]))
    pathlib.Path("/app/index.html").write_bytes(base64.b64decode(os.environ["INDEX_B64"]))
    PY
    ${local.ecs_pip_install_command}
    python /app/server.py
  EOT
  )
}

resource "aws_ecs_cluster" "factor" {
  name = local.ecs_cluster_name
  tags = local.tags
}

resource "aws_security_group" "ecs_tasks" {
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
  name = "/ecs/${local.ecs_cluster_name}/process"
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "persist" {
  name = "/ecs/${local.ecs_cluster_name}/persist"
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "test_msg" {
  name = "/ecs/${local.ecs_cluster_name}/test-msg"
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "web" {
  name = "/ecs/${local.ecs_cluster_name}/web"
  tags = local.tags
}

resource "aws_ecs_task_definition" "process" {
  family                   = "${local.ecs_cluster_name}-process"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name       = "process"
      image      = var.ecs_image
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
          awslogs-group         = aws_cloudwatch_log_group.process.name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "persist" {
  family                   = "${local.ecs_cluster_name}-persist"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name       = "persist"
      image      = var.ecs_image
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
          awslogs-group         = aws_cloudwatch_log_group.persist.name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "test_msg" {
  family                   = "${local.ecs_cluster_name}-test-msg"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name       = "test-msg"
      image      = var.ecs_image
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
          awslogs-group         = aws_cloudwatch_log_group.test_msg.name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${local.ecs_cluster_name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name       = "web"
      image      = var.ecs_image
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.web_command]
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "SERVER_B64"
          value = local.web_server_script_b64
        },
        {
          name  = "INDEX_B64"
          value = local.web_index_b64
        },
        {
          name  = "PORT"
          value = "8000"
        },
        {
          name  = "FACTOR_DB_NAME"
          value = var.web_db_name
        }
      ]
      secrets = [
        {
          name      = "FACTOR_DB_USER"
          valueFrom = "${aws_secretsmanager_secret.cs_rds_credentials.arn}:username::"
        },
        {
          name      = "FACTOR_DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.cs_rds_credentials.arn}:password::"
        },
        {
          name      = "FACTOR_DB_HOST"
          valueFrom = "${aws_secretsmanager_secret.cs_rds_credentials.arn}:host::"
        },
        {
          name      = "FACTOR_DB_PORT"
          valueFrom = "${aws_secretsmanager_secret.cs_rds_credentials.arn}:port::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "process" {
  name            = "${local.ecs_cluster_name}-process"
  cluster         = aws_ecs_cluster.factor.id
  task_definition = aws_ecs_task_definition.process.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_selected.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.ecs_assign_public_ip
  }
}

resource "aws_ecs_service" "persist" {
  name            = "${local.ecs_cluster_name}-persist"
  cluster         = aws_ecs_cluster.factor.id
  task_definition = aws_ecs_task_definition.persist.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_selected.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.ecs_assign_public_ip
  }
}

resource "aws_ecs_service" "test_msg" {
  name            = "${local.ecs_cluster_name}-test-msg"
  cluster         = aws_ecs_cluster.factor.id
  task_definition = aws_ecs_task_definition.test_msg.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_selected.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.ecs_assign_public_ip
  }
}

resource "aws_ecs_service" "web" {
  name            = "${local.ecs_cluster_name}-web"
  cluster         = aws_ecs_cluster.factor.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_selected.ids
    security_groups  = [aws_security_group.web_tasks.id]
    assign_public_ip = var.ecs_assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 8000
  }
}

resource "aws_cloudwatch_event_rule" "test_msg" {
  name                = "${local.ecs_cluster_name}-test-msg"
  schedule_expression = var.ecs_test_msg_schedule
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "test_msg" {
  rule      = aws_cloudwatch_event_rule.test_msg.name
  target_id = "${local.ecs_cluster_name}-test-msg"
  arn       = aws_ecs_cluster.factor.arn
  role_arn  = aws_iam_role.ecs_events.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.test_msg.arn
    task_count          = 1
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = data.aws_subnets.public_selected.ids
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = var.ecs_assign_public_ip
    }
  }
}
