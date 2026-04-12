################################################################################
# GPU Node Group — sandbox-compatible wiring
#
# Production target:  g4dn.xlarge / p3.2xlarge  +  ami_type = AL2_x86_64_GPU
# Sandbox override:   t3.medium                 +  ami_type = AL2023_x86_64_STANDARD
#
# The node taint (nvidia.com/gpu=true:NoSchedule), labels, and NVIDIA device
# plugin Helm release are fully configured for GPU production use. Flipping
# instance_types and ami_type below is the only change required when GPU quota
# becomes available.
################################################################################

module "eks_gpu" {
  source = "../modules/eks-gpu"

  node_group_name        = "gpu-west"
  cluster_name           = module.eks_cluster.cluster_name
  cluster_service_cidr   = module.eks_cluster.cluster_service_cidr
  node_security_group_id = module.eks_cluster.node_security_group_id
  subnet_ids             = data.aws_subnets.eks_public.ids

  # -----------------------------------------------------------------------
  # Sandbox overrides — remove these two lines and restore the defaults
  # (g4dn.xlarge / AL2_x86_64_GPU) once GPU quota is available.
  # -----------------------------------------------------------------------
  instance_types = ["t3.medium"]
  ami_type       = "AL2023_x86_64_STANDARD"

  # desired_size = 0 keeps the node group defined without launching instances.
  # Scale up via the AWS console or by bumping desired_size once quota exists.
  min_size     = 0
  max_size     = 2
  desired_size = 0

  disk_size_gb = 100
  kms_key_arn  = aws_kms_key.eks_ebs.arn

  iam_role_additional_policies = {
    ecr_scoped_pull = aws_iam_policy.eks_ecr_pull.arn
    ebs_kms         = aws_iam_policy.eks_node_kms.arn
  }

  nvidia_device_plugin_version = "0.17.0"

  tags = {
    Environment = "Dev"
    Project     = "FlaskApp"
  }

  depends_on = [helm_release.cilium]
}
