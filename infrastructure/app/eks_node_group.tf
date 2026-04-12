module "eks_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "21.15.1"

  name         = "general-purpose"
  cluster_name = module.eks_cluster.cluster_name

  vpc_security_group_ids = [module.eks_cluster.node_security_group_id]
  cluster_service_cidr   = module.eks_cluster.cluster_service_cidr

  subnet_ids     = data.aws_subnets.eks_public.ids
  ami_type       = "AL2023_ARM_64_STANDARD"
  instance_types = ["t4g.medium"]
  min_size       = 1
  max_size       = 1
  desired_size   = 1

  iam_role_additional_policies = {
    ecr_scoped_pull = aws_iam_policy.eks_ecr_pull.arn
    ebs_kms         = aws_iam_policy.eks_node_kms.arn
  }

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 20
        volume_type           = "gp3"
        encrypted             = true
        kms_key_id            = aws_kms_key.eks_ebs.arn
        delete_on_termination = true
      }
    }
  }

  tags = {
    Environment = "Dev"
    Project     = "FlaskApp"
  }

  depends_on = [helm_release.cilium]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks_node_group]
}

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = module.eks_cluster.cluster_version
  most_recent        = true
}
