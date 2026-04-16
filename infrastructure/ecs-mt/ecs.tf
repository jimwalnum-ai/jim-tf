################################################################################
# Shared cluster infrastructure
################################################################################

resource "aws_ecs_cluster" "factor_mt" {
  name = local.ecs_cluster_name
  tags = local.tags
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.ecs_cluster_name}-tasks"
  description = "ECS tasks for multitenant factor workloads"
  vpc_id      = data.aws_vpc.dev-vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #trivy:ignore:AVD-AWS-0104
  }

  tags = local.tags
}

################################################################################
# Locals — per-tenant script payloads and commands
################################################################################

locals {
  process_script_b64  = base64encode(file("${path.module}/../code/process.py"))
  persist_script_b64  = base64encode(file("${path.module}/../code/persist.py"))
  test_msg_script_b64 = base64encode(file("${path.module}/../code/test_msg.py"))

  pip_install = "pip install --no-cache-dir boto3==1.42.49 botocore==1.42.49 \"urllib3<2.0\" psycopg2-binary"

  process_command = trimspace(<<-EOT
    set -e
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/run.py").write_bytes(base64.b64decode(os.environ["SCRIPT_B64"]))
    PY
    ${local.pip_install}
    while true; do python /app/run.py || true; sleep 5; done
  EOT
  )

  persist_command = trimspace(<<-EOT
    set -e
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/run.py").write_bytes(base64.b64decode(os.environ["SCRIPT_B64"]))
    PY
    ${local.pip_install}
    while true; do python /app/run.py || true; sleep 5; done
  EOT
  )

  test_msg_command = trimspace(<<-EOT
    set -e
    python - <<'PY'
    import base64, os, pathlib
    pathlib.Path("/app").mkdir(parents=True, exist_ok=True)
    pathlib.Path("/app/run.py").write_bytes(base64.b64decode(os.environ["SCRIPT_B64"]))
    PY
    ${local.pip_install}
    python /app/run.py
  EOT
  )
}

################################################################################
# Per-tenant CloudWatch log groups
################################################################################

resource "aws_cloudwatch_log_group" "process" {
  for_each = var.tenants
  name     = "/ecs/${local.ecs_cluster_name}/${each.key}/process"
  tags     = local.tags
}

resource "aws_cloudwatch_log_group" "persist" {
  for_each = var.tenants
  name     = "/ecs/${local.ecs_cluster_name}/${each.key}/persist"
  tags     = local.tags
}

resource "aws_cloudwatch_log_group" "test_msg" {
  for_each = var.tenants
  name     = "/ecs/${local.ecs_cluster_name}/${each.key}/test-msg"
  tags     = local.tags
}

################################################################################
# Per-tenant task definitions
################################################################################

resource "aws_ecs_task_definition" "process" {
  for_each                 = var.tenants
  family                   = "${local.ecs_cluster_name}-${each.key}-process"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.process_cpu
  memory                   = each.value.process_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([
    {
      name       = "process"
      image      = var.ecs_image
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.process_command]
      environment = [
        { name = "SCRIPT_B64", value = local.process_script_b64 },
        { name = "TENANT_ID", value = each.key },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.process[each.key].name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "persist" {
  for_each                 = var.tenants
  family                   = "${local.ecs_cluster_name}-${each.key}-persist"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.task_cpu
  memory                   = each.value.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([
    {
      name       = "persist"
      image      = var.ecs_image
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.persist_command]
      environment = [
        { name = "SCRIPT_B64", value = local.persist_script_b64 },
        { name = "TENANT_ID", value = each.key },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.persist[each.key].name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "test_msg" {
  for_each                 = var.tenants
  family                   = "${local.ecs_cluster_name}-${each.key}-test-msg"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.task_cpu
  memory                   = each.value.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([
    {
      name       = "test-msg"
      image      = var.ecs_image
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.test_msg_command]
      environment = [
        { name = "SCRIPT_B64", value = local.test_msg_script_b64 },
        { name = "TENANT_ID", value = each.key },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.test_msg[each.key].name
          awslogs-region        = data.aws_region.current.id
          awslogs-create-group  = "true"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

################################################################################
# Per-tenant ECS services
################################################################################

resource "aws_ecs_service" "process" {
  for_each        = var.tenants
  name            = "${local.ecs_cluster_name}-${each.key}-process"
  cluster         = aws_ecs_cluster.factor_mt.id
  task_definition = aws_ecs_task_definition.process[each.key].arn
  desired_count   = each.value.process_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_selected.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.ecs_assign_public_ip
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "persist" {
  for_each        = var.tenants
  name            = "${local.ecs_cluster_name}-${each.key}-persist"
  cluster         = aws_ecs_cluster.factor_mt.id
  task_definition = aws_ecs_task_definition.persist[each.key].arn
  desired_count   = each.value.persist_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_selected.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.ecs_assign_public_ip
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "test_msg" {
  for_each        = var.tenants
  name            = "${local.ecs_cluster_name}-${each.key}-test-msg"
  cluster         = aws_ecs_cluster.factor_mt.id
  task_definition = aws_ecs_task_definition.test_msg[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_selected.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.ecs_assign_public_ip
  }
}

################################################################################
# Per-tenant scheduled test_msg task (EventBridge)
################################################################################

resource "aws_cloudwatch_event_rule" "test_msg" {
  for_each            = var.tenants
  name                = "${local.ecs_cluster_name}-${each.key}-test-msg"
  schedule_expression = var.ecs_test_msg_schedule
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "test_msg" {
  for_each  = var.tenants
  rule      = aws_cloudwatch_event_rule.test_msg[each.key].name
  target_id = "${local.ecs_cluster_name}-${each.key}-test-msg"
  arn       = aws_ecs_cluster.factor_mt.arn
  role_arn  = aws_iam_role.ecs_events[each.key].arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.test_msg[each.key].arn
    task_count          = 1
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = data.aws_subnets.public_selected.ids
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = var.ecs_assign_public_ip
    }
  }
}
