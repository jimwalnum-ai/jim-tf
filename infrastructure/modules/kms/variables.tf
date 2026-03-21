variable "key_name" {
  type        = string
  description = "Key Name (alias)"
}

variable "write_roles" {
  type        = list(any)
  description = "Write Roles"
}

variable "readonly_roles" {
  type        = list(any)
  description = "Read Roles"
}

variable "tags" {
  type        = map(string)
  description = "Tags for key (opt)"
  default     = {}
}

variable "autoscaling_service_role_arn_pattern" {
  type        = string
  description = "Auto Scaling service-linked role ARN pattern for KMS grant operations"
}

variable "eks_node_role_arn_pattern" {
  type        = list(string)
  description = "EKS node IAM role ARN pattern(s) for KMS usage"
}