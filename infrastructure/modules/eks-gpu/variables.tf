variable "node_group_name" {
  description = "Name of the EKS managed node group."
  type        = string
  default     = "gpu"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_service_cidr" {
  description = "CIDR block for Kubernetes services (from cluster output)."
  type        = string
}

variable "node_security_group_id" {
  description = "ID of the EKS-managed node security group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs where GPU nodes will be placed."
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Instance type — override to "t3.medium" / "t3.large" in sandbox environments
# that do not have GPU quota. The taint, labels, and device plugin DaemonSet
# are fully wired for production (p3.2xlarge / g4dn.xlarge) use.
# ---------------------------------------------------------------------------
variable "instance_types" {
  description = "EC2 instance types for the GPU node group. Use g4dn.xlarge or p3.2xlarge in production."
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

# ---------------------------------------------------------------------------
# AMI type — use AL2_x86_64_GPU in production so NVIDIA drivers are
# pre-installed. Override to AL2023_x86_64_STANDARD in sandboxes that
# lack GPU instances.
# ---------------------------------------------------------------------------
variable "ami_type" {
  description = "AMI type for GPU nodes. Use AL2_x86_64_GPU in production; AL2023_x86_64_STANDARD for sandbox overrides."
  type        = string
  default     = "AL2_x86_64_GPU"
}

variable "min_size" {
  description = "Minimum number of GPU nodes."
  type        = number
  default     = 0
}

variable "max_size" {
  description = "Maximum number of GPU nodes."
  type        = number
  default     = 4
}

variable "desired_size" {
  description = "Desired number of GPU nodes. Set to 0 in sandbox to avoid launching instances."
  type        = number
  default     = 1
}

variable "disk_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 100
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt node EBS volumes."
  type        = string
}

variable "iam_role_additional_policies" {
  description = "Map of additional IAM policy ARNs to attach to the node IAM role."
  type        = map(string)
  default     = {}
}

variable "nvidia_device_plugin_version" {
  description = "Helm chart version for the NVIDIA device plugin."
  type        = string
  default     = "0.17.0"
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
