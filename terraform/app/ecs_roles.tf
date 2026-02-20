locals {
  factor_queue_name        = "SQS_FACTOR_DEV"
  factor_result_queue_name = "SQS_FACTOR_RESULT_DEV"
}

data "aws_sqs_queue" "factor_dev" {
  name = local.factor_queue_name
}

data "aws_sqs_queue" "factor_result_dev" {
  name = local.factor_result_queue_name
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.ecs_cluster_name}-task-role"
  assume_role_policy = templatefile("${path.module}/templates/ecs_task_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${local.ecs_cluster_name}-task-policy"
  role = aws_iam_role.ecs_task.id
  policy = templatefile("${path.module}/templates/ecs_task_policy.json.tpl", {
    factor_queue_arn        = data.aws_sqs_queue.factor_dev.arn
    factor_result_queue_arn = data.aws_sqs_queue.factor_result_dev.arn
    rds_secret_arn          = aws_secretsmanager_secret.cs_rds_credentials.arn
  })
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.ecs_cluster_name}-task-execution"
  assume_role_policy = templatefile("${path.module}/templates/ecs_task_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.ecs_cluster_name}-task-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id
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
  name   = "${local.ecs_cluster_name}-task-execution-logs"
  role   = aws_iam_role.ecs_task_execution.id
  policy = templatefile("${path.module}/templates/ecs_task_execution_logs_policy.json.tpl", {})
}

resource "aws_iam_role" "ecs_events" {
  name               = "${local.ecs_cluster_name}-events"
  assume_role_policy = templatefile("${path.module}/templates/ecs_events_assume_role.json.tpl", {})
  tags               = local.tags
}

resource "aws_iam_role_policy" "ecs_events" {
  name = "${local.ecs_cluster_name}-events-policy"
  role = aws_iam_role.ecs_events.id
  policy = templatefile("${path.module}/templates/ecs_events_policy.json.tpl", {
    ecs_task_definition_arn     = aws_ecs_task_definition.test_msg.arn
    ecs_cluster_arn             = aws_ecs_cluster.factor.arn
    ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
    ecs_task_role_arn           = aws_iam_role.ecs_task.arn
  })
}
