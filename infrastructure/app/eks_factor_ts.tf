################################################################################
# SQS Queues — TypeScript Factor Pipeline
################################################################################

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

################################################################################
# Outputs
################################################################################

output "factor_ts_sqs_queue_name" {
  value       = aws_sqs_queue.factor_ts.name
  description = "SQS queue name for the TypeScript factor pipeline"
}

output "factor_ts_sqs_result_queue_name" {
  value       = aws_sqs_queue.factor_result_ts.name
  description = "SQS result queue name for the TypeScript factor pipeline"
}
