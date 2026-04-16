
################################################################################
# IRSA — Dashboard (S3 read-only for reports)
################################################################################

locals {
  dashboard_namespace = local.security_agent_namespace
  dashboard_sa_name   = "cilium-security-dashboard"
}

resource "aws_iam_policy" "security_dashboard" {
  count       = local.enable_eks ? 1 : 0
  name        = "${module.eks_cluster[0].cluster_name}-security-dashboard"
  description = "Allow the security dashboard to read reports and flow logs from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadReports"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          module.hubble_logs_bucket[0].bucket_arn,
          "${module.hubble_logs_bucket[0].bucket_arn}/*",
        ]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role" "security_dashboard" {
  count = local.enable_eks ? 1 : 0
  name  = "${module.eks_cluster[0].cluster_name}-security-dashboard"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks_cluster[0].oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks_cluster[0].oidc_provider}:aud" = "sts.amazonaws.com"
            "${module.eks_cluster[0].oidc_provider}:sub" = "system:serviceaccount:${local.dashboard_namespace}:${local.dashboard_sa_name}"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "security_dashboard" {
  count      = local.enable_eks ? 1 : 0
  role       = aws_iam_role.security_dashboard[0].name
  policy_arn = aws_iam_policy.security_dashboard[0].arn
}

################################################################################
# Kubernetes — Service Account, Deployment, Service
################################################################################

resource "kubernetes_service_account_v1" "security_dashboard" {
  count = local.enable_eks ? 1 : 0

  metadata {
    name      = local.dashboard_sa_name
    namespace = local.dashboard_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.security_dashboard[0].arn
    }
  }

  depends_on = [kubernetes_namespace_v1.security]
}

resource "kubernetes_deployment_v1" "security_dashboard" {
  count = local.enable_eks ? 1 : 0

  metadata {
    name      = "cilium-security-dashboard"
    namespace = local.dashboard_namespace
  }

  wait_for_rollout = false

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cilium-security-dashboard"
      }
    }

    template {
      metadata {
        labels = {
          app = "cilium-security-dashboard"
        }
      }

      spec {
        service_account_name = local.dashboard_sa_name

        container {
          name              = "dashboard"
          image             = "${aws_ecr_repository.security_dashboard.repository_url}:latest"
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          env {
            name  = "S3_BUCKET"
            value = module.hubble_logs_bucket[0].bucket_name
          }
          env {
            name  = "REPORTS_PREFIX"
            value = "security-reports/"
          }
          env {
            name  = "AWS_REGION"
            value = data.aws_region.current.id
          }
          env {
            name  = "CLUSTER_NAME"
            value = module.eks_cluster[0].cluster_name
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            timeout_seconds       = 3
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 3
            timeout_seconds       = 3
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account_v1.security_dashboard,
    aws_iam_role_policy_attachment.security_dashboard,
  ]
}

resource "kubernetes_service_v1" "security_dashboard" {
  count = local.enable_eks ? 1 : 0

  metadata {
    name      = "cilium-security-dashboard"
    namespace = local.dashboard_namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }

  spec {
    selector = {
      app = "cilium-security-dashboard"
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_namespace_v1.security]
}

################################################################################
# Outputs
################################################################################

output "security_dashboard_ecr_url" {
  value       = aws_ecr_repository.security_dashboard.repository_url
  description = "ECR repository URL for the security dashboard image"
}

output "security_dashboard_url" {
  value       = local.enable_eks ? try("http://${kubernetes_service_v1.security_dashboard[0].status[0].load_balancer[0].ingress[0].hostname}", "(pending)") : (local.enable_ecs_web ? "http://${aws_lb.security_dashboard[0].dns_name}" : "(disabled)")
  description = "URL to access the Cilium security dashboard"
}

output "security_dashboard_url_hostname" {
  value       = local.enable_eks ? try(kubernetes_service_v1.security_dashboard[0].status[0].load_balancer[0].ingress[0].hostname, "") : (local.enable_ecs_web ? aws_lb.security_dashboard[0].dns_name : "")
  description = "Raw hostname for the security dashboard (used by global Route 53)"
}
