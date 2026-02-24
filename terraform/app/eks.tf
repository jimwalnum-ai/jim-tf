
module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.0.0"

  name               = "eks-cluster"
  kubernetes_version = "1.34"
  vpc_id             = data.aws_vpc.dev-vpc.id
  subnet_ids         = data.aws_subnets.private_selected.ids
  enable_irsa        = true

  # EKS Managed Node Group
  eks_managed_node_groups = {
    general_purpose = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      # Ensure subnets are private for production best practices
      subnet_ids = data.aws_subnets.private_selected.ids
      iam_role_additional_policies = {
        ecr_readonly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }

  tags = {
    Environment = "Dev"
    Project     = "FlaskApp"
  }
}