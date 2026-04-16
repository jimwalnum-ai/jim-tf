locals {
  ecr_repos_base = {
    flask_app      = aws_ecr_repository.flask_app
    factor_process = aws_ecr_repository.factor_process
    factor_persist = aws_ecr_repository.factor_persist
    factor_test_msg = aws_ecr_repository.factor_test_msg
  }
  ecr_repos_eks = local.enable_eks ? {
    security_agent          = aws_ecr_repository.security_agent[0]
    security_dashboard      = aws_ecr_repository.security_dashboard[0]
    observability_dashboard = aws_ecr_repository.observability_dashboard[0]
  } : {}
  ecr_repos_ecs_web = local.enable_ecs_web ? {
    security_dashboard      = aws_ecr_repository.security_dashboard[0]
    observability_dashboard = aws_ecr_repository.observability_dashboard[0]
  } : {}
  ecr_repos = merge(local.ecr_repos_base, local.ecr_repos_eks, local.ecr_repos_ecs_web)
}

# Scoped IAM policy: EKS nodes can only pull from our specific repos
resource "aws_iam_policy" "eks_ecr_pull" {
  count       = local.enable_eks ? 1 : 0
  name        = "eks-ecr-pull-scoped"
  description = "Allow EKS nodes to pull images only from designated ECR repositories"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAuthToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowPullFromScopedRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [for repo in local.ecr_repos : repo.arn]
      }
    ]
  })

  tags = local.tags
}

# ECR repository policy for flask-app
resource "aws_ecr_repository_policy" "flask_app" {
  count      = local.enable_eks ? 1 : 0
  repository = aws_ecr_repository.flask_app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEKSNodePull"
        Effect = "Allow"
        Principal = {
          AWS = module.eks_node_group[0].iam_role_arn
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      },
      {
        Sid    = "AllowTerraformRolePush"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/cs-terraform-role"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}

# Lifecycle policy: keep only the last 10 images per repo
resource "aws_ecr_lifecycle_policy" "flask_app" {
  repository = aws_ecr_repository.flask_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
