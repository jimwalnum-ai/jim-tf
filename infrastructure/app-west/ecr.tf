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
  description = "ECR repository URL for the Flask app image (us-west-2, populated via replication)."
}

resource "aws_ecr_repository" "factor_process" {
  name                 = "factor-process"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_repository" "factor_persist" {
  name                 = "factor-persist"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_repository" "factor_test_msg" {
  name                 = "factor-test-msg"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}
