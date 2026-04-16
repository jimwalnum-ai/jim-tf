################################################################################
# GPU Node Group — sandbox-compatible wiring (us-east-1)
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
  count  = local.enable_eks ? 1 : 0
  source = "../modules/eks-gpu"

  node_group_name        = "gpu"
  cluster_name           = module.eks_cluster[0].cluster_name
  cluster_service_cidr   = module.eks_cluster[0].cluster_service_cidr
  node_security_group_id = module.eks_cluster[0].node_security_group_id
  subnet_ids             = data.aws_subnets.eks_public[0].ids

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
  kms_key_arn  = aws_kms_key.eks_ebs[0].arn

  iam_role_additional_policies = {
    ecr_scoped_pull = aws_iam_policy.eks_ecr_pull[0].arn
    ebs_kms         = aws_iam_policy.eks_node_kms[0].arn
  }

  nvidia_device_plugin_version = "0.17.0"

  tags = {
    Environment = "Dev"
    Project     = "FlaskApp"
  }

  depends_on = [helm_release.cilium]
}
