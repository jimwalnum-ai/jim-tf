variable "eks_cluster_name" {
  type        = string
  default     = null
  description = "EKS cluster name to use API auth instead of kubeconfig."
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for EKS lookup (uses AWS_REGION/AWS_DEFAULT_REGION if null)."
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "Optional AWS profile name for authentication."
}

variable "kubeconfig_path" {
  type        = string
  default     = "~/.kube/config"
  description = "Path to the kubeconfig file (used when eks_cluster_name is null)."
}

variable "kubeconfig_context" {
  type        = string
  default     = null
  description = "Optional kubeconfig context name (used when eks_cluster_name is null)."
}

variable "namespace" {
  type        = string
  default     = "factor-workloads"
  description = "Namespace to deploy workloads into."
}

variable "release_name" {
  type        = string
  default     = "factor-workloads"
  description = "Helm release name."
}

variable "chart_path" {
  type        = string
  default     = null
  description = "Local path to the factor-workloads Helm chart."
}

variable "values" {
  type        = any
  default     = {}
  description = "Additional Helm values overrides."
}
