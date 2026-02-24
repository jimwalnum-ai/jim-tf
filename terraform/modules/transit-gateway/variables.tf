variable "env" {
  type        = string
  description = "Env"
}

variable "tags" {
  type        = map(string)
  description = "Tags"
  default     = {}
}

variable "flow_log_bucket" {
  type        = string
  description = "S3 bucket ARN for transit gateway flow logs"
}