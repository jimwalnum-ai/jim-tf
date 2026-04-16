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

resource "aws_ecr_repository" "factor_worker" {
  name                 = "factor-worker"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "factor_worker" {
  repository = aws_ecr_repository.factor_worker.name
  policy     = local.factor_ecr_lifecycle_policy
}

output "factor_worker_ecr_repository_url" {
  value       = aws_ecr_repository.factor_worker.repository_url
  description = "ECR repository URL for the factor worker image."
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

resource "aws_ecr_repository" "security_agent" {
  name                 = "cilium-security-agent"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "security_agent" {
  repository = aws_ecr_repository.security_agent.name
  policy     = local.factor_ecr_lifecycle_policy
}

output "cilium_security_agent_ecr_repository_url" {
  value       = aws_ecr_repository.security_agent.repository_url
  description = "ECR repository URL for the Cilium security agent image."
}

resource "aws_ecr_repository" "security_dashboard" {
  name                 = "cilium-security-dashboard"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "security_dashboard" {
  repository = aws_ecr_repository.security_dashboard.name
  policy     = local.factor_ecr_lifecycle_policy
}

output "cilium_security_dashboard_ecr_repository_url" {
  value       = aws_ecr_repository.security_dashboard.repository_url
  description = "ECR repository URL for the Cilium security dashboard image."
}

resource "aws_ecr_repository" "observability_dashboard" {
  name                 = "observability-dashboard"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "observability_dashboard" {
  repository = aws_ecr_repository.observability_dashboard.name
  policy     = local.factor_ecr_lifecycle_policy
}

output "observability_dashboard_ecr_repository_url" {
  value       = aws_ecr_repository.observability_dashboard.repository_url
  description = "ECR repository URL for the observability dashboard image."
}
