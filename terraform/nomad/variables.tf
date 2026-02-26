variable "env" {
  type    = string
  default = "dev"
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
  default     = 2
}

variable "client_max_count" {
  description = "Maximum number of Nomad client nodes the autoscaler can scale to."
  type        = number
  default     = 5
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

variable "rds_secret_name" {
  type    = string
  default = "cs-factor-credentials"
}

variable "process_max_count" {
  description = "Maximum number of factor-process allocations the SQS scaler can create."
  type        = number
  default     = 6
}

variable "persist_max_count" {
  description = "Maximum number of factor-persist allocations the SQS scaler can create."
  type        = number
  default     = 4
}

variable "msgs_per_instance" {
  description = "Number of SQS messages per allocation before scaling up."
  type        = number
  default     = 100
}

locals {
  name_prefix      = "nomad-${var.env}"
  ssh_public_key   = trimspace(file("/Users/jameswalnum/.ssh/id_ed25519.pub"))
  home_ip          = chomp(file("../../ip.txt"))
}
