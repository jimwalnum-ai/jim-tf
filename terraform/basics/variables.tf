variable "ecs_task_role_arn" {
  description = "ECS task role ARN allowed to access SQS queues."
  type        = string
  default     = ""
}

variable "eks_workloads_role_arn" {
  description = "EKS workloads role ARN allowed to access SQS queues."
  type        = string
  default     = ""
}
