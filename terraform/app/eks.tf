variable "env" {
  type        = string
  description = "Environment name (e.g. dev, prd)."
  default     = "dev"
}

variable "eks_cluster_name" {
  type        = string
  description = "Optional EKS cluster name override."
  default     = null
}

variable "eks_tgw_subnet_ids" {
  type        = list(string)
  description = "TGW subnet IDs from the dev VPC for the EKS control plane."
  default     = null
}

variable "eks_kubernetes_version" {
  type        = string
  description = "Kubernetes version for the cluster and node groups."
  default     = "1.34"
}

variable "eks_node_group_name" {
  type        = string
  description = "Node group name."
  default     = "default"
}

variable "eks_instance_types" {
  type        = list(string)
  description = "EC2 instance types for the node group."
  default     = ["t3.medium"]
}

variable "eks_capacity_type" {
  type        = string
  description = "Node group capacity type (ON_DEMAND or SPOT)."
  default     = "ON_DEMAND"
}

variable "eks_desired_size" {
  type        = number
  description = "Desired node count."
  default     = 2
}

variable "eks_min_size" {
  type        = number
  description = "Minimum node count."
  default     = 1
}

variable "eks_max_size" {
  type        = number
  description = "Maximum node count."
  default     = 3
}

variable "eks_endpoint_private_access" {
  type        = bool
  description = "Enable private endpoint access."
  default     = true
}

variable "eks_endpoint_public_access" {
  type        = bool
  description = "Enable public endpoint access."
  default     = false
}

data "aws_subnets" "tgw" {
  filter {
    name   = "tag:type"
    values = ["tgw"]
  }

  filter {
    name   = "tag:Name"
    values = ["*-${var.env}-tgw-subnet-*"]
  }
}

locals {
  eks_cluster_name = var.eks_cluster_name != null && var.eks_cluster_name != "" ? var.eks_cluster_name : "eks-cluster-${var.env}"
  eks_subnet_ids   = var.eks_tgw_subnet_ids != null && length(var.eks_tgw_subnet_ids) > 0 ? var.eks_tgw_subnet_ids : data.aws_subnets.tgw.ids
}

module "eks_dev" {
  source = "../modules/eks"

  cluster_name       = local.eks_cluster_name
  kubernetes_version = var.eks_kubernetes_version
  subnet_ids         = local.eks_subnet_ids

  node_group_name = var.eks_node_group_name
  instance_types  = var.eks_instance_types
  desired_size    = var.eks_desired_size
  min_size        = var.eks_min_size
  max_size        = var.eks_max_size
  capacity_type   = var.eks_capacity_type

  endpoint_private_access = var.eks_endpoint_private_access
  endpoint_public_access  = var.eks_endpoint_public_access

  tags = local.tags
}
