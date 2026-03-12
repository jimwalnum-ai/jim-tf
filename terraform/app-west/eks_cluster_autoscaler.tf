locals {
  cluster_autoscaler_namespace = "kube-system"
  cluster_autoscaler_sa_name   = "cluster-autoscaler"
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${module.eks_cluster.cluster_name}-cluster-autoscaler"
  description = "IAM policy for Cluster Autoscaler on ${module.eks_cluster.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AutoscalingReadOnly"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Sid    = "AutoscalingMutate"
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${module.eks_cluster.cluster_name}" = "owned"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role" "cluster_autoscaler" {
  name = "${module.eks_cluster.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks_cluster.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks_cluster.oidc_provider}:aud" = "sts.amazonaws.com"
            "${module.eks_cluster.oidc_provider}:sub" = "system:serviceaccount:${local.cluster_autoscaler_namespace}:${local.cluster_autoscaler_sa_name}"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = local.cluster_autoscaler_namespace
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.55.1"

  set = [
    { name = "autoDiscovery.clusterName", value = module.eks_cluster.cluster_name },
    { name = "awsRegion", value = data.aws_region.current.id },
    { name = "rbac.serviceAccount.create", value = "true" },
    { name = "rbac.serviceAccount.name", value = local.cluster_autoscaler_sa_name },
    { name = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = aws_iam_role.cluster_autoscaler.arn },
    { name = "extraArgs.balance-similar-node-groups", value = "true" },
    { name = "extraArgs.skip-nodes-with-system-pods", value = "false" },
    { name = "extraArgs.scale-down-unneeded-time", value = "5m" },
    { name = "extraArgs.scale-down-delay-after-add", value = "5m" },
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_autoscaler,
    module.eks_node_group
  ]
}
