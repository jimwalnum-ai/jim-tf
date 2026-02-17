data "aws_eks_cluster_auth" "cluster" {
  name       = module.eks_dev.cluster_name
  depends_on = [module.eks_dev]
}

data "aws_iam_role" "node_role" {
  name       = "${module.eks_dev.cluster_name}-node-role"
  depends_on = [module.eks_dev]
}

provider "kubernetes" {
  host                   = module.eks_dev.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_dev.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

variable "aws_auth_additional_roles" {
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default     = []
  description = "Additional IAM roles to add to aws-auth mapRoles."
}

variable "aws_auth_additional_users" {
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default     = []
  description = "Additional IAM users to add to aws-auth mapUsers."
}

variable "aws_auth_additional_accounts" {
  type        = list(string)
  default     = []
  description = "Additional AWS account IDs to add to aws-auth mapAccounts."
}

locals {
  aws_auth_roles = concat([
    {
      rolearn  = data.aws_iam_role.node_role.arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ], var.aws_auth_additional_roles)
}

resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = merge(
    {
      mapRoles = yamlencode(local.aws_auth_roles)
    },
    length(var.aws_auth_additional_users) > 0 ? { mapUsers = yamlencode(var.aws_auth_additional_users) } : {},
    length(var.aws_auth_additional_accounts) > 0 ? { mapAccounts = yamlencode(var.aws_auth_additional_accounts) } : {}
  )

  depends_on = [module.eks_dev]
}
