locals {
  cluster_autoscaler_namespace = "kube-system"
  cluster_autoscaler_sa_name   = "cluster-autoscaler"
  # Use the legacy OIDC provider that matches the cluster's actual token issuer URL
  legacy_oidc_provider_url = replace(aws_iam_openid_connect_provider.eks_legacy_oidc.arn, "/^arn:.*:oidc-provider\\//", "")
}

# IAM policy granting the Cluster Autoscaler permission to inspect and modify ASGs
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

# IRSA role: allows the Cluster Autoscaler service account to assume this role via OIDC
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${module.eks_cluster.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_legacy_oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.legacy_oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${local.legacy_oidc_provider_url}:sub" = "system:serviceaccount:${local.cluster_autoscaler_namespace}:${local.cluster_autoscaler_sa_name}"
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

# Deploy Cluster Autoscaler via Helm
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = local.cluster_autoscaler_namespace
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.43.2"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks_cluster.cluster_name
  }
  set {
    name  = "awsRegion"
    value = data.aws_region.current.id
  }
  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = local.cluster_autoscaler_sa_name
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }
  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }
  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "5m"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_autoscaler,
    module.eks_cluster
  ]
}
