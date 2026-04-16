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

locals {
  factor_ecr_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_repository" "factor_process" {
  name                 = "factor-process"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "factor_process" {
  repository = aws_ecr_repository.factor_process.name
  policy     = local.factor_ecr_lifecycle_policy
}

output "factor_process_ecr_repository_url" {
  value       = aws_ecr_repository.factor_process.repository_url
  description = "ECR repository URL for the factor process image."
}

resource "aws_ecr_repository" "factor_persist" {
  name                 = "factor-persist"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "factor_persist" {
  repository = aws_ecr_repository.factor_persist.name
  policy     = local.factor_ecr_lifecycle_policy
}

output "factor_persist_ecr_repository_url" {
  value       = aws_ecr_repository.factor_persist.repository_url
  description = "ECR repository URL for the factor persist image."
}

resource "aws_ecr_repository" "factor_test_msg" {
  name                 = "factor-test-msg"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "factor_test_msg" {
  repository = aws_ecr_repository.factor_test_msg.name
  policy     = local.factor_ecr_lifecycle_policy
}

output "factor_test_msg_ecr_repository_url" {
  value       = aws_ecr_repository.factor_test_msg.repository_url
  description = "ECR repository URL for the factor test_msg image."
}
