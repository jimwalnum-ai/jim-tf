################################################################################
# GPU-enabled EKS Managed Node Group
#
# Provisions a node group configured for NVIDIA GPU workloads:
#   • Taint  nvidia.com/gpu=true:NoSchedule  keeps non-GPU pods off these nodes
#   • Label  nvidia.com/gpu=true             lets nodeSelectors target the pool
#   • AL2_x86_64_GPU AMI pre-installs NVIDIA drivers (override in sandboxes)
################################################################################

module "gpu_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "21.15.1"

  name         = var.node_group_name
  cluster_name = var.cluster_name

  vpc_security_group_ids = [var.node_security_group_id]
  cluster_service_cidr   = var.cluster_service_cidr

  subnet_ids     = var.subnet_ids
  ami_type       = var.ami_type
  instance_types = var.instance_types
  min_size       = var.min_size
  max_size       = var.max_size
  desired_size   = var.desired_size

  # Taint prevents non-GPU pods from landing on expensive GPU nodes.
  # Workloads must declare a matching toleration (see manifests/gpu-test-pod.yaml).
  taints = {
    nvidia_gpu = {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  labels = {
    "nvidia.com/gpu" = "true"
  }

  iam_role_additional_policies = var.iam_role_additional_policies

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = var.disk_size_gb
        volume_type           = "gp3"
        encrypted             = true
        kms_key_id            = var.kms_key_arn
        delete_on_termination = true
      }
    }
  }

  tags = merge(var.tags, { "GpuReady" = "true" })
}
