variable "env" {
  type    = string
  default = "dev"
}

variable "server_count" {
  description = "Number of Nomad/Consul server nodes (use 3 or 5 for HA)."
  type        = number
  default     = 1
}

variable "server_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "client_instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "client_cpu_total_compute" {
  description = "Override Nomad CPU fingerprint (MHz). Needed for burstable instance types where Nomad detects 0 MHz."
  type        = number
  default     = 4000
}

variable "client_min_count" {
  description = "Minimum number of Nomad client nodes in the ASG."
  type        = number
  default     = 3
}

variable "client_max_count" {
  description = "Maximum number of Nomad client nodes the autoscaler can scale to."
  type        = number
  default     = 12
}

variable "nomad_autoscaler_version" {
  type    = string
  default = "0.4.5"
}

variable "nomad_version" {
  type    = string
  default = "1.9.7"
}

variable "consul_version" {
  type    = string
  default = "1.20.6"
}

variable "cni_plugins_version" {
  type    = string
  default = "1.6.2"
}

variable "docker_tasks_image" {
  description = "Container image for factor job tasks."
  type        = string
  default     = "python:3.11-slim"
}

variable "factor_queue_name" {
  type    = string
  default = "SQS_FACTOR_DEV"
}

variable "factor_result_queue_name" {
  type    = string
  default = "SQS_FACTOR_RESULT_DEV"
}

variable "factor_ts_queue_name" {
  type    = string
  default = "SQS_FACTOR_TS_DEV"
}

variable "factor_ts_result_queue_name" {
  type    = string
  default = "SQS_FACTOR_RESULT_TS_DEV"
}

variable "rds_secret_name" {
  type    = string
  default = "cs-factor-credentials"
}

variable "process_min_count" {
  description = "Minimum number of factor-process allocations kept running."
  type        = number
  default     = 2
}

variable "process_max_count" {
  description = "Maximum number of factor-process allocations the SQS scaler can create."
  type        = number
  default     = 10
}

variable "persist_min_count" {
  description = "Minimum number of factor-persist allocations kept running."
  type        = number
  default     = 2
}

variable "persist_max_count" {
  description = "Maximum number of factor-persist allocations the SQS scaler can create."
  type        = number
  default     = 10
}

variable "process_ts_min_count" {
  description = "Minimum number of factor-process-ts allocations kept running."
  type        = number
  default     = 2
}

variable "process_ts_max_count" {
  description = "Maximum number of factor-process-ts allocations the SQS scaler can create."
  type        = number
  default     = 10
}

variable "persist_ts_min_count" {
  description = "Minimum number of factor-persist-ts allocations kept running."
  type        = number
  default     = 2
}

variable "persist_ts_max_count" {
  description = "Maximum number of factor-persist-ts allocations the SQS scaler can create."
  type        = number
  default     = 10
}

variable "msgs_per_instance" {
  description = "Number of SQS messages per allocation before scaling up."
  type        = number
  default     = 100
}


locals {
  name_prefix         = "nomad-${var.env}"
  home_ip             = chomp(file("../../ip.txt"))
  enabled             = var.enable_nomad ? 1 : 0
  server_actual_count = var.enable_nomad ? var.server_count : 0
}
