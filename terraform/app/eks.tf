################################################################################
# KMS Key for EKS Node EBS Encryption
################################################################################

resource "aws_kms_key" "eks_ebs" {
  description             = "KMS key for EKS node EBS volume encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.eks_ebs_kms.json

  tags = {
    Environment = "Dev"
    Project     = "FlaskApp"
  }
}

resource "aws_kms_alias" "eks_ebs" {
  name          = "alias/eks-node-ebs"
  target_key_id = aws_kms_key.eks_ebs.key_id
}

data "aws_iam_policy_document" "eks_ebs_kms" {
  statement {
    sid       = "EnableRootAccountAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowAutoScalingServiceLinkedRole"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
      ]
    }
  }

  statement {
    sid       = "AllowAutoScalingCreateGrant"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
      ]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "eks_node_kms" {
  name        = "eks-node-ebs-kms"
  description = "Allow EKS nodes to use KMS key for EBS encryption"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKMSForEBS"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = [aws_kms_key.eks_ebs.arn]
      }
    ]
  })

  tags = local.tags
}

################################################################################
# Subnets
################################################################################

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
  version = "21.15.1"

  name               = "eks-cluster"
  kubernetes_version = "1.35"
  vpc_id             = data.aws_vpc.dev-vpc.id
  subnet_ids         = concat(data.aws_subnets.tgw_selected.ids, data.aws_subnets.eks_public.ids)
  enable_irsa        = true

  addons = {
    coredns = {
      most_recent = true
    }
  }

  endpoint_private_access = true
  endpoint_public_access  = true

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  node_security_group_additional_rules = {
    ingress_nlb_nodeport = {
      description = "Allow NLB health checks and traffic on NodePort range"
      protocol    = "tcp"
      from_port   = 30000
      to_port     = 32767
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = {
    Environment = "Dev"
    Project     = "FlaskApp"
  }
}