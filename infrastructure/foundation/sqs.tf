resource "aws_sqs_queue" "factor_dev" {
  name                       = "SQS_FACTOR_DEV"
  redrive_policy             = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.results_updates_dl_queue.arn}\",\"maxReceiveCount\":5}"
  visibility_timeout_seconds = 300
  tags                       = local.tags
}

resource "aws_sqs_queue" "factor_result_dev" {
  name                       = "SQS_FACTOR_RESULT_DEV"
  redrive_policy             = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.results_updates_dl_queue.arn}\",\"maxReceiveCount\":10}"
  visibility_timeout_seconds = 300
  tags                       = local.tags
}

resource "aws_sqs_queue" "factor_ts" {
  name                       = "SQS_FACTOR_TS_DEV"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  tags                       = local.tags
}

resource "aws_sqs_queue" "factor_result_ts" {
  name                       = "SQS_FACTOR_RESULT_TS_DEV"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600
  tags                       = local.tags
}

resource "aws_sqs_queue" "results_updates_dl_queue" {
  name = "SQS_FACTOR_DLQ"
  tags = local.tags
}

locals {
  sqs_allowed_principals = distinct(compact([
    "arn:aws:iam::${local.acct_id}:role/cs-terraform-role",
    var.ecs_task_role_arn,
    var.eks_workloads_role_arn
  ]))
}

data "aws_iam_policy_document" "sqs_access_factor_dev" {
  statement {
    sid    = "SqsAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.sqs_allowed_principals
    }
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      aws_sqs_queue.factor_dev.arn
    ]
  }
}

data "aws_iam_policy_document" "sqs_access_factor_result_dev" {
  statement {
    sid    = "SqsAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.sqs_allowed_principals
    }
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      aws_sqs_queue.factor_result_dev.arn
    ]
  }
}

data "aws_iam_policy_document" "sqs_access_results_updates_dl_queue" {
  statement {
    sid    = "SqsAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.sqs_allowed_principals
    }
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      aws_sqs_queue.results_updates_dl_queue.arn
    ]
  }
}

resource "aws_sqs_queue_policy" "factor_queue_policy" {
  queue_url = aws_sqs_queue.factor_dev.id
  policy    = data.aws_iam_policy_document.sqs_access_factor_dev.json
}

resource "aws_sqs_queue_policy" "factor_result_queue_policy" {
  queue_url = aws_sqs_queue.factor_result_dev.id
  policy    = data.aws_iam_policy_document.sqs_access_factor_result_dev.json
}

resource "aws_sqs_queue_policy" "results_updates_dl_queue_policy" {
  queue_url = aws_sqs_queue.results_updates_dl_queue.id
  policy    = data.aws_iam_policy_document.sqs_access_results_updates_dl_queue.json
}

data "aws_iam_policy_document" "sqs_access_factor_ts" {
  statement {
    sid    = "SqsAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.sqs_allowed_principals
    }
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      aws_sqs_queue.factor_ts.arn
    ]
  }
}

data "aws_iam_policy_document" "sqs_access_factor_result_ts" {
  statement {
    sid    = "SqsAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.sqs_allowed_principals
    }
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      aws_sqs_queue.factor_result_ts.arn
    ]
  }
}

resource "aws_sqs_queue_policy" "factor_ts_queue_policy" {
  queue_url = aws_sqs_queue.factor_ts.id
  policy    = data.aws_iam_policy_document.sqs_access_factor_ts.json
}

resource "aws_sqs_queue_policy" "factor_result_ts_queue_policy" {
  queue_url = aws_sqs_queue.factor_result_ts.id
  policy    = data.aws_iam_policy_document.sqs_access_factor_result_ts.json
}