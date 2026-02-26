resource "aws_ecr_repository" "flask_app" {
  name                 = "flask-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

output "flask_app_ecr_repository_url" {
  value       = aws_ecr_repository.flask_app.repository_url
  description = "ECR repository URL for the Flask app image."
}

resource "aws_ecr_repository" "stress_test" {
  name                 = "stress-test"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

output "stress_test_ecr_repository_url" {
  value       = aws_ecr_repository.stress_test.repository_url
  description = "ECR repository URL for the stress-test image."
}
