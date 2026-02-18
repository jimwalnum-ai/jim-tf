{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecs:RunTask",
      "Resource": "${ecs_task_definition_arn}",
      "Condition": {
        "ArnEquals": {
          "ecs:cluster": "${ecs_cluster_arn}"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "${ecs_task_execution_role_arn}",
        "${ecs_task_role_arn}"
      ]
    }
  ]
}
