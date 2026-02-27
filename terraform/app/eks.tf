data "aws_subnets" "tgw_selected" {
  filter {
    name   = "tag:scope"
    values = ["private"]
  }
  filter {
    name   = "tag:type"
    values = ["tgw"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev-vpc.id]
  }
}

data "aws_subnets" "eks_public" {
  filter {
    name   = "tag:scope"
    values = ["public"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.dev-vpc.id]
  }
}

module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.0.0"

  name               = "eks-cluster"
  kubernetes_version = "1.34"
  vpc_id             = data.aws_vpc.dev-vpc.id
  subnet_ids         = concat(data.aws_subnets.tgw_selected.ids, data.aws_subnets.eks_public.ids)
  enable_irsa        = true

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }
  }

  endpoint_private_access = true
  endpoint_public_access  = true

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  # EKS Managed Node Group
  eks_managed_node_groups = {
    general_purpose = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 5
      desired_size   = 1
      subnet_ids     = data.aws_subnets.eks_public.ids
      iam_role_additional_policies = {
        ecr_scoped_pull = aws_iam_policy.eks_ecr_pull.arn
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = false
            delete_on_termination = true
          }
        }
      }
    }
  }

  tags = {
    Environment = "Dev"
    Project     = "FlaskApp"
  }
}