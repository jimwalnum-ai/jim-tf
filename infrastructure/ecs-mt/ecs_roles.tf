################################################################################
# SQS queue data sources — one per tenant queue
################################################################################

data "aws_sqs_queue" "factor" {
  for_each = var.tenants
  name     = each.value.factor_queue_name
}

data "aws_sqs_queue" "factor_result" {
  for_each = var.tenants
  name     = each.value.factor_result_queue_name
}

################################################################################
# Shared task execution role
# Needs access to all tenant secrets so it can inject them at container start.
################################################################################

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.ecs_cluster_name}-task-execution"
  assume_role_policy = templatefile(
    "${path.module}/templates/ecs_task_assume_role.json.tpl", {}
  )
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.ecs_cluster_name}-task-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [for t in var.tenants : t.rds_secret_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_execution_logs" {
  name = "${local.ecs_cluster_name}-task-execution-logs"
  role = aws_iam_role.ecs_task_execution.id
  policy = templatefile(
    "${path.module}/templates/ecs_task_execution_logs_policy.json.tpl", {}
  )
}

################################################################################
# Per-tenant task roles — scoped to only that tenant's queues and secret
################################################################################

resource "aws_iam_role" "ecs_task" {
  for_each = var.tenants
  name     = "${local.ecs_cluster_name}-${each.key}-task-role"
  assume_role_policy = templatefile(
    "${path.module}/templates/ecs_task_assume_role.json.tpl", {}
  )
  tags = local.tags
}

resource "aws_iam_role_policy" "ecs_task" {
  for_each = var.tenants
  name     = "${local.ecs_cluster_name}-${each.key}-task-policy"
  role     = aws_iam_role.ecs_task[each.key].id
  policy = templatefile("${path.module}/templates/ecs_task_policy.json.tpl", {
    factor_queue_arn        = data.aws_sqs_queue.factor[each.key].arn
    factor_result_queue_arn = data.aws_sqs_queue.factor_result[each.key].arn
    rds_secret_arn          = each.value.rds_secret_arn
  })
}

################################################################################
# Per-tenant EventBridge roles — allow CloudWatch Events to trigger ECS tasks
################################################################################

resource "aws_iam_role" "ecs_events" {
  for_each = var.tenants
  name     = "${local.ecs_cluster_name}-${each.key}-events"
  assume_role_policy = templatefile(
    "${path.module}/templates/ecs_events_assume_role.json.tpl", {}
  )
  tags = local.tags
}

resource "aws_iam_role_policy" "ecs_events" {
  for_each = var.tenants
  name     = "${local.ecs_cluster_name}-${each.key}-events-policy"
  role     = aws_iam_role.ecs_events[each.key].id
  policy = templatefile("${path.module}/templates/ecs_events_policy.json.tpl", {
    ecs_task_definition_arn     = aws_ecs_task_definition.test_msg[each.key].arn
    ecs_cluster_arn             = aws_ecs_cluster.factor_mt.arn
    ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
    ecs_task_role_arn           = aws_iam_role.ecs_task[each.key].arn
  })
}
