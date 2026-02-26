locals {
  factor_queue_name        = "SQS_FACTOR_DEV"
  factor_result_queue_name = "SQS_FACTOR_RESULT_DEV"
}

data "aws_sqs_queue" "factor_dev" {
  count = local.enable_ecs ? 1 : 0
  name  = local.factor_queue_name
}

data "aws_sqs_queue" "factor_result_dev" {
  count = local.enable_ecs ? 1 : 0
  name  = local.factor_result_queue_name
}

resource "aws_iam_role" "ecs_task" {
  count              = local.enable_ecs ? 1 : 0
  name               = "${local.ecs_cluster_name}-task-role"
  assume_role_policy = templatefile("${path.module}/templates/ecs_task_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy" "ecs_task" {
  count = local.enable_ecs ? 1 : 0
  name  = "${local.ecs_cluster_name}-task-policy"
  role  = aws_iam_role.ecs_task[0].id
  policy = templatefile("${path.module}/templates/ecs_task_policy.json.tpl", {
    factor_queue_arn        = data.aws_sqs_queue.factor_dev[0].arn
    factor_result_queue_arn = data.aws_sqs_queue.factor_result_dev[0].arn
    rds_secret_arn          = aws_secretsmanager_secret.cs_rds_credentials.arn
  })
}

resource "aws_iam_role" "ecs_task_execution" {
  count              = local.enable_ecs ? 1 : 0
  name               = "${local.ecs_cluster_name}-task-execution"
  assume_role_policy = templatefile("${path.module}/templates/ecs_task_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  count      = local.enable_ecs ? 1 : 0
  role       = aws_iam_role.ecs_task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  count = local.enable_ecs ? 1 : 0
  name  = "${local.ecs_cluster_name}-task-execution-secrets"
  role  = aws_iam_role.ecs_task_execution[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = [aws_secretsmanager_secret.cs_rds_credentials.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_execution_logs" {
  count  = local.enable_ecs ? 1 : 0
  name   = "${local.ecs_cluster_name}-task-execution-logs"
  role   = aws_iam_role.ecs_task_execution[0].id
  policy = templatefile("${path.module}/templates/ecs_task_execution_logs_policy.json.tpl", {})
}

resource "aws_iam_role" "ecs_events" {
  count              = local.enable_ecs ? 1 : 0
  name               = "${local.ecs_cluster_name}-events"
  assume_role_policy = templatefile("${path.module}/templates/ecs_events_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy" "ecs_events" {
  count = local.enable_ecs ? 1 : 0
  name  = "${local.ecs_cluster_name}-events-policy"
  role  = aws_iam_role.ecs_events[0].id
  policy = templatefile("${path.module}/templates/ecs_events_policy.json.tpl", {
    ecs_task_definition_arn     = aws_ecs_task_definition.test_msg[0].arn
    ecs_cluster_arn             = aws_ecs_cluster.factor[0].arn
    ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution[0].arn
    ecs_task_role_arn           = aws_iam_role.ecs_task[0].arn
  })
}
