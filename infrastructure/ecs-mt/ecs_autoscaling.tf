################################################################################
# Per-tenant autoscaling — process and persist services scale on SQS depth
################################################################################

resource "aws_appautoscaling_target" "process" {
  for_each           = var.tenants
  max_capacity       = var.ecs_autoscaling_max
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.factor_mt.name}/${aws_ecs_service.process[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "process_scale_up" {
  for_each           = var.tenants
  name               = "${local.ecs_cluster_name}-${each.key}-process-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.process[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.process[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.process[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = 1
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 500
    }
    step_adjustment {
      scaling_adjustment          = 2
      metric_interval_lower_bound = 500
    }
  }
}

resource "aws_appautoscaling_policy" "process_scale_down" {
  for_each           = var.tenants
  name               = "${local.ecs_cluster_name}-${each.key}-process-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.process[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.process[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.process[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = -1
      metric_interval_upper_bound = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "process_queue_high" {
  for_each            = var.tenants
  alarm_name          = "${local.ecs_cluster_name}-${each.key}-factor-queue-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 100
  alarm_actions       = [aws_appautoscaling_policy.process_scale_up[each.key].arn]
  dimensions = {
    QueueName = each.value.factor_queue_name
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "process_queue_low" {
  for_each            = var.tenants
  alarm_name          = "${local.ecs_cluster_name}-${each.key}-factor-queue-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 10
  alarm_actions       = [aws_appautoscaling_policy.process_scale_down[each.key].arn]
  dimensions = {
    QueueName = each.value.factor_queue_name
  }
  tags = local.tags
}

resource "aws_appautoscaling_target" "persist" {
  for_each           = var.tenants
  max_capacity       = var.ecs_autoscaling_max
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.factor_mt.name}/${aws_ecs_service.persist[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "persist_scale_up" {
  for_each           = var.tenants
  name               = "${local.ecs_cluster_name}-${each.key}-persist-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.persist[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.persist[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.persist[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = 1
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 500
    }
    step_adjustment {
      scaling_adjustment          = 2
      metric_interval_lower_bound = 500
    }
  }
}

resource "aws_appautoscaling_policy" "persist_scale_down" {
  for_each           = var.tenants
  name               = "${local.ecs_cluster_name}-${each.key}-persist-scale-down"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.persist[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.persist[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.persist[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = -1
      metric_interval_upper_bound = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "persist_queue_high" {
  for_each            = var.tenants
  alarm_name          = "${local.ecs_cluster_name}-${each.key}-result-queue-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 100
  alarm_actions       = [aws_appautoscaling_policy.persist_scale_up[each.key].arn]
  dimensions = {
    QueueName = each.value.factor_result_queue_name
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "persist_queue_low" {
  for_each            = var.tenants
  alarm_name          = "${local.ecs_cluster_name}-${each.key}-result-queue-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 10
  alarm_actions       = [aws_appautoscaling_policy.persist_scale_down[each.key].arn]
  dimensions = {
    QueueName = each.value.factor_result_queue_name
  }
  tags = local.tags
}
