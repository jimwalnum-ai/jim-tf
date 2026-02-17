variable "cluster_name" {
  type        = string
  description = "EKS cluster name."
  default     = "eks-cluster-dev"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the cluster and node groups."
  default     = "1.34"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the EKS cluster control plane."
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires at least two subnets in different AZs."
  }
}

variable "node_subnet_ids" {
  type        = list(string)
  description = "Optional subnet IDs for worker nodes (defaults to subnet_ids)."
  default     = null
}

variable "node_group_name" {
  type        = string
  description = "Node group name."
  default     = "default"
}

variable "instance_types" {
  type        = list(string)
  description = "EC2 instance types for the node group."
  default     = ["t3.medium"]
}

variable "desired_size" {
  type        = number
  description = "Desired node count."
  default     = 2
}

variable "min_size" {
  type        = number
  description = "Minimum node count."
  default     = 1
}

variable "max_size" {
  type        = number
  description = "Maximum node count."
  default     = 3
}

variable "capacity_type" {
  type        = string
  description = "Node group capacity type (ON_DEMAND or SPOT)."
  default     = "SPOT"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "endpoint_private_access" {
  type        = bool
  description = "Enable private endpoint access."
  default     = true
}

variable "endpoint_public_access" {
  type        = bool
  description = "Enable public endpoint access."
  default     = false
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to access the public endpoint."
  default     = []
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Control plane log types to enable."
  default     = ["api", "audit", "authenticator"]
}

variable "max_unavailable" {
  type        = number
  description = "Maximum unavailable nodes during updates."
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
