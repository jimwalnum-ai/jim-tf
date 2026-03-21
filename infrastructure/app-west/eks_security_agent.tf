################################################################################
# ECR Repository — Security Agent Image
################################################################################

resource "aws_ecr_repository" "security_agent" {
  name                 = "cilium-security-agent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "security_agent" {
  repository = aws_ecr_repository.security_agent.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = { type = "expire" }
      }
    ]
  })
}

################################################################################
# SNS Topic — Security Alerts
################################################################################

resource "aws_sns_topic" "security_alerts" {
  name = "${module.eks_cluster.cluster_name}-cilium-security-alerts"
  tags = local.tags
}

variable "security_alert_email" {
  description = "Email address for security alert notifications (leave empty to skip)"
  type        = string
  default     = ""
}

resource "aws_sns_topic_subscription" "security_email" {
  count     = var.security_alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

################################################################################
# IRSA — Security Agent (S3 read + Bedrock invoke + SNS publish)
################################################################################

locals {
  security_agent_namespace = "security"
  security_agent_sa_name   = "cilium-security-agent"
}

resource "aws_iam_policy" "security_agent" {
  name        = "${module.eks_cluster.cluster_name}-cilium-security-agent"
  description = "Allow the Cilium security agent to read Hubble logs from S3, invoke Bedrock, and publish to SNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadHubbleLogs"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          module.hubble_logs_bucket.bucket_arn,
          "${module.hubble_logs_bucket.bucket_arn}/*",
        ]
      },
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.id}::foundation-model/anthropic.claude-3-5-haiku-20241022-v1:0",
        ]
      },
      {
        Sid    = "SNSPublishAlerts"
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ]
        Resource = [aws_sns_topic.security_alerts.arn]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role" "security_agent" {
  name = "${module.eks_cluster.cluster_name}-cilium-security-agent"

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
            "${module.eks_cluster.oidc_provider}:sub" = "system:serviceaccount:${local.security_agent_namespace}:${local.security_agent_sa_name}"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "security_agent" {
  role       = aws_iam_role.security_agent.name
  policy_arn = aws_iam_policy.security_agent.arn
}

################################################################################
# Kubernetes — Namespace + CronJob
################################################################################

resource "kubernetes_namespace_v1" "security" {
  metadata {
    name = local.security_agent_namespace
  }

  depends_on = [module.eks_node_group]
}

resource "kubernetes_cron_job_v1" "security_agent" {
  metadata {
    name      = "cilium-security-agent"
    namespace = local.security_agent_namespace
  }

  spec {
    schedule                      = "*/3 * * * *"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
    concurrency_policy            = "Forbid"

    job_template {
      metadata {}
      spec {
        backoff_limit = 1

        template {
          metadata {
            labels = {
              app = "cilium-security-agent"
            }
          }
          spec {
            service_account_name = local.security_agent_sa_name
            restart_policy       = "Never"

            container {
              name              = "agent"
              image             = "${data.terraform_remote_state.app_east.outputs.security_agent_ecr_url}:latest"
              image_pull_policy = "Always"

              env {
                name  = "S3_BUCKET"
                value = module.hubble_logs_bucket.bucket_name
              }
              env {
                name  = "S3_PREFIX"
                value = "hubble/logs/"
              }
              env {
                name  = "AWS_REGION"
                value = data.aws_region.current.id
              }
              env {
                name  = "SNS_TOPIC_ARN"
                value = aws_sns_topic.security_alerts.arn
              }
              env {
                name  = "BEDROCK_MODEL_ID"
                value = "anthropic.claude-3-5-haiku-20241022-v1:0"
              }
              env {
                name  = "CLUSTER_NAME"
                value = module.eks_cluster.cluster_name
              }
              env {
                name  = "LOOKBACK_MINUTES"
                value = "5"
              }
              env {
                name  = "REPORTS_PREFIX"
                value = "security-reports/"
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace_v1.security,
    aws_iam_role_policy_attachment.security_agent,
  ]
}

resource "kubernetes_service_account_v1" "security_agent" {
  metadata {
    name      = local.security_agent_sa_name
    namespace = local.security_agent_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.security_agent.arn
    }
  }

  depends_on = [kubernetes_namespace_v1.security]
}

################################################################################
# Build & Push Agent Image (omitted — images replicated from us-east-1 via ECR replication)
################################################################################

output "security_agent_ecr_url" {
  value       = aws_ecr_repository.security_agent.repository_url
  description = "ECR repository URL for the Cilium security agent image (us-west-2)"
}

output "security_alerts_topic_arn" {
  value       = aws_sns_topic.security_alerts.arn
  description = "SNS topic ARN for Cilium security alerts (us-west-2)"
}
