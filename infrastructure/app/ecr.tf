resource "aws_ecr_repository" "flask_app" {
  name                 = "flask-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

output "flask_app_ecr_repository_url" {
  value       = aws_ecr_repository.flask_app.repository_url
  description = "ECR repository URL for the Flask app image."
}

resource "aws_ecr_repository" "factor_worker" {
  name                 = "factor-worker"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "factor_worker" {
  repository = aws_ecr_repository.factor_worker.name

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

output "factor_worker_ecr_repository_url" {
  value       = aws_ecr_repository.factor_worker.repository_url
  description = "ECR repository URL for the factor worker image."
}
