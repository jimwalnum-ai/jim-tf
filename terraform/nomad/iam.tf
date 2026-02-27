data "aws_sqs_queue" "factor" {
  name = var.factor_queue_name
}

data "aws_sqs_queue" "factor_result" {
  name = var.factor_result_queue_name
}

resource "aws_iam_role" "nomad_node" {
  name = "${local.name_prefix}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "nomad_sqs" {
  name = "${local.name_prefix}-sqs"
  role = aws_iam_role.nomad_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:DeleteMessageBatch",
        "sqs:SendMessage",
        "sqs:SendMessageBatch",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ChangeMessageVisibility"
      ]
      Resource = [
        data.aws_sqs_queue.factor.arn,
        data.aws_sqs_queue.factor_result.arn
      ]
    }]
  })
}

resource "aws_iam_role_policy" "nomad_secrets" {
  name = "${local.name_prefix}-secrets"
  role = aws_iam_role.nomad_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = ["arn:aws:secretsmanager:${data.aws_region.current.id}:${local.acct_id}:secret:${var.rds_secret_name}-*"]
    }]
  })
}

resource "aws_iam_role_policy" "nomad_logs" {
  name = "${local.name_prefix}-logs"
  role = aws_iam_role.nomad_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = ["arn:aws:logs:*:${local.acct_id}:log-group:/nomad/*"]
    }]
  })
}

resource "aws_iam_role_policy" "nomad_autoscaler" {
  name = "${local.name_prefix}-autoscaler"
  role = aws_iam_role.nomad_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ASGScaling"
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:CreateOrUpdateTags",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = ["*"]
      },
      {
        Sid    = "SQSMetrics"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          data.aws_sqs_queue.factor.arn,
          data.aws_sqs_queue.factor_result.arn
        ]
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "nomad_cloud_auto_join" {
  name = "${local.name_prefix}-cloud-auto-join"
  role = aws_iam_role.nomad_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances"
      ]
      Resource = ["*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nomad_ssm" {
  role       = aws_iam_role.nomad_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nomad_node" {
  name = "${local.name_prefix}-node"
  role = aws_iam_role.nomad_node.name
}
