variable "ecs_image" {
  type        = string
  description = "Container image for the factor scripts (set to ECR URL after first build)."
  default     = "python:3.11-slim"
}

variable "ecs_assign_public_ip" {
  type        = bool
  description = "Assign public IPs to ECS tasks."
  default     = true
}

variable "ecs_autoscaling_max" {
  type        = number
  description = "Maximum number of tasks per service per tenant for autoscaling."
  default     = 6
}

variable "ecs_test_msg_schedule" {
  type        = string
  description = "Schedule expression for the test_msg scheduled task."
  default     = "rate(30 minutes)"
}

variable "tenants" {
  description = "Map of tenant configurations. Key is the tenant identifier (e.g. \"acme\", \"globex\")."
  type = map(object({
    factor_queue_name        = string
    factor_result_queue_name = string
    rds_secret_arn           = string

    process_cpu           = optional(string, "2048")
    process_memory        = optional(string, "4096")
    task_cpu              = optional(string, "256")
    task_memory           = optional(string, "512")
    process_desired_count = optional(number, 2)
    persist_desired_count = optional(number, 2)
  }))
  default = {}
}
