locals {
  ecr_repos = {
    flask_app   = aws_ecr_repository.flask_app
    stress_test = aws_ecr_repository.stress_test
  }
}

# Scoped IAM policy: EKS nodes can only pull from our specific repos
resource "aws_iam_policy" "eks_ecr_pull" {
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
  repository = aws_ecr_repository.flask_app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEKSNodePull"
        Effect    = "Allow"
        Principal = {
          AWS = module.eks_cluster.eks_managed_node_groups["general_purpose"].iam_role_arn
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      },
      {
        Sid       = "AllowAccountPush"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
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

# ECR repository policy for stress-test
resource "aws_ecr_repository_policy" "stress_test" {
  repository = aws_ecr_repository.stress_test.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEKSNodePull"
        Effect    = "Allow"
        Principal = {
          AWS = module.eks_cluster.eks_managed_node_groups["general_purpose"].iam_role_arn
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      },
      {
        Sid       = "AllowAccountPush"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
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

resource "aws_ecr_lifecycle_policy" "stress_test" {
  repository = aws_ecr_repository.stress_test.name

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
