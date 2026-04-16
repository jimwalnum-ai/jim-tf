locals {
  ecr_repos = {
    flask_app               = aws_ecr_repository.flask_app
    factor_worker           = aws_ecr_repository.factor_worker
    factor_process          = aws_ecr_repository.factor_process
    factor_persist          = aws_ecr_repository.factor_persist
    factor_test_msg         = aws_ecr_repository.factor_test_msg
    security_agent          = aws_ecr_repository.security_agent
    security_dashboard      = aws_ecr_repository.security_dashboard
    observability_dashboard = aws_ecr_repository.observability_dashboard
  }
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

locals {
  github_actions_role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-ecr-push"
  ci_push_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "ecr:PutImage",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
  ]
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
        Action = local.ci_push_actions
      },
      {
        Sid    = "AllowGitHubActionsPush"
        Effect = "Allow"
        Principal = {
          AWS = local.github_actions_role_arn
        }
        Action = local.ci_push_actions
      }
    ]
  })
}

# ECR repository policies for factor images — grant GitHub Actions push access
resource "aws_ecr_repository_policy" "factor_worker" {
  repository = aws_ecr_repository.factor_worker.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGitHubActionsPush"
      Effect    = "Allow"
      Principal = { AWS = local.github_actions_role_arn }
      Action    = local.ci_push_actions
    }]
  })
}

resource "aws_ecr_repository_policy" "factor_process" {
  repository = aws_ecr_repository.factor_process.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGitHubActionsPush"
      Effect    = "Allow"
      Principal = { AWS = local.github_actions_role_arn }
      Action    = local.ci_push_actions
    }]
  })
}

resource "aws_ecr_repository_policy" "factor_persist" {
  repository = aws_ecr_repository.factor_persist.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGitHubActionsPush"
      Effect    = "Allow"
      Principal = { AWS = local.github_actions_role_arn }
      Action    = local.ci_push_actions
    }]
  })
}

resource "aws_ecr_repository_policy" "factor_test_msg" {
  repository = aws_ecr_repository.factor_test_msg.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGitHubActionsPush"
      Effect    = "Allow"
      Principal = { AWS = local.github_actions_role_arn }
      Action    = local.ci_push_actions
    }]
  })
}

resource "aws_ecr_repository_policy" "security_agent" {
  repository = aws_ecr_repository.security_agent.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGitHubActionsPush"
      Effect    = "Allow"
      Principal = { AWS = local.github_actions_role_arn }
      Action    = local.ci_push_actions
    }]
  })
}

resource "aws_ecr_repository_policy" "security_dashboard" {
  repository = aws_ecr_repository.security_dashboard.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGitHubActionsPush"
      Effect    = "Allow"
      Principal = { AWS = local.github_actions_role_arn }
      Action    = local.ci_push_actions
    }]
  })
}

resource "aws_ecr_repository_policy" "observability_dashboard" {
  repository = aws_ecr_repository.observability_dashboard.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowGitHubActionsPush"
      Effect    = "Allow"
      Principal = { AWS = local.github_actions_role_arn }
      Action    = local.ci_push_actions
    }]
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
