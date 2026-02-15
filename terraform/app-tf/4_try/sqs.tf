resource "aws_sqs_queue" "factor_dev" {
    name = "SQS_FACTOR_DEV"
    redrive_policy  = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.results_updates_dl_queue.arn}\",\"maxReceiveCount\":5}"
    visibility_timeout_seconds = 300
    tags = local.tags
}

resource "aws_sqs_queue" "factor_result_dev" {
    name = "SQS_FACTOR_RESULT_DEV"
    redrive_policy  = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.results_updates_dl_queue.arn}\",\"maxReceiveCount\":10}"
    visibility_timeout_seconds = 300
    tags = local.tags
}

resource "aws_sqs_queue" "results_updates_dl_queue" {
    name = "SQS_FACTOR_DLQ"
    tags = local.tags
}

resource "aws_sqs_queue_policy" "factor_queue_policy" {
    queue_url = "${aws_sqs_queue.factor_dev.id}"
    policy = data.template_file.sqs_policy.rendered
}

data "template_file" "sqs_policy" {
  template = file("${path.module}/templates/sqs_policy.json.tpl")
  vars = {
    allowed_role = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
    acct = local.acct_id
  }
}