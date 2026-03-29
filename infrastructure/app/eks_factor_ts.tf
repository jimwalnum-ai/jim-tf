################################################################################
# SQS Queues — TypeScript Factor Pipeline (managed by foundation)
################################################################################

data "aws_sqs_queue" "factor_ts" {
  name = "SQS_FACTOR_TS_DEV"
}

data "aws_sqs_queue" "factor_result_ts" {
  name = "SQS_FACTOR_RESULT_TS_DEV"
}

################################################################################
# Outputs
################################################################################

output "factor_ts_sqs_queue_name" {
  value       = data.aws_sqs_queue.factor_ts.name
  description = "SQS queue name for the TypeScript factor pipeline"
}

output "factor_ts_sqs_result_queue_name" {
  value       = data.aws_sqs_queue.factor_result_ts.name
  description = "SQS result queue name for the TypeScript factor pipeline"
}
