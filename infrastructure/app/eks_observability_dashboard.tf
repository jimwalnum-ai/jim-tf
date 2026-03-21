################################################################################
# ECR Repository — Observability Dashboard Image
################################################################################

resource "aws_ecr_repository" "observability_dashboard" {
  name                 = "observability-dashboard"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "observability_dashboard" {
  repository = aws_ecr_repository.observability_dashboard.name

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
# Remote state — read Nomad ALB DNS for dashboard config
################################################################################

data "terraform_remote_state" "nomad" {
  backend = "s3"
  config = {
    bucket = local.state_bucket_name
    key    = "nomad/state.tfstate"
    region = "us-east-1"
  }
}

################################################################################
# IRSA — Observability Dashboard
################################################################################

locals {
  obs_namespace = "observability"
  obs_sa_name   = "observability-dashboard"
}

resource "aws_iam_policy" "observability_dashboard" {
  name        = "${module.eks_cluster.cluster_name}-observability-dashboard"
  description = "Allow the observability dashboard to read AWS resource status"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData",
        ]
        Resource = "*"
      },
      {
        Sid    = "SQSRead"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
        ]
        Resource = "*"
      },
      {
        Sid    = "RDSRead"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSPublish"
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

resource "aws_iam_role" "observability_dashboard" {
  name = "${module.eks_cluster.cluster_name}-observability-dashboard"

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
            "${module.eks_cluster.oidc_provider}:sub" = "system:serviceaccount:${local.obs_namespace}:${local.obs_sa_name}"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "observability_dashboard" {
  role       = aws_iam_role.observability_dashboard.name
  policy_arn = aws_iam_policy.observability_dashboard.arn
}

################################################################################
# Kubernetes — Namespace, RBAC, Service Account, Deployment, Service
################################################################################

resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = local.obs_namespace
  }

  depends_on = [module.eks_node_group]
}

resource "kubernetes_service_account_v1" "observability_dashboard" {
  metadata {
    name      = local.obs_sa_name
    namespace = local.obs_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.observability_dashboard.arn
    }
  }

  depends_on = [kubernetes_namespace_v1.observability]
}

resource "kubernetes_cluster_role_v1" "observability_reader" {
  metadata {
    name = "observability-reader"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "nodes", "events", "services", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "daemonsets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "observability_reader" {
  metadata {
    name = "observability-reader"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.observability_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = local.obs_sa_name
    namespace = local.obs_namespace
  }
}

resource "kubernetes_deployment_v1" "observability_dashboard" {
  metadata {
    name      = "observability-dashboard"
    namespace = local.obs_namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "observability-dashboard"
      }
    }

    template {
      metadata {
        labels = {
          app = "observability-dashboard"
        }
        annotations = {
          "src-hash" = local.obs_src_hash
        }
      }

      spec {
        service_account_name = local.obs_sa_name

        container {
          name              = "dashboard"
          image             = "${aws_ecr_repository.observability_dashboard.repository_url}:latest"
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          env {
            name  = "AWS_REGION"
            value = data.aws_region.current.id
          }
          env {
            name  = "CLUSTER_NAME"
            value = module.eks_cluster.cluster_name
          }
          env {
            name  = "NOMAD_ADDR"
            value = "http://${try(data.terraform_remote_state.nomad.outputs.alb_dns_name, "")}:4646"
          }
          env {
            name  = "SQS_QUEUE_NAMES"
            value = "SQS_FACTOR_DEV,SQS_FACTOR_RESULT_DEV"
          }
          env {
            name  = "RDS_INSTANCE_ID"
            value = aws_db_instance.factor.identifier
          }
          env {
            name  = "SNS_TOPIC_ARN"
            value = aws_sns_topic.security_alerts.arn
          }
          env {
            name  = "NOMAD_IGNORED_DEAD_JOBS"
            value = "sqs-scaler"
          }
          env {
            name  = "POLL_INTERVAL"
            value = "10"
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
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account_v1.observability_dashboard,
    kubernetes_cluster_role_binding_v1.observability_reader,
    aws_iam_role_policy_attachment.observability_dashboard,
    terraform_data.observability_dashboard_image,
  ]
}

resource "kubernetes_service_v1" "observability_dashboard" {
  metadata {
    name      = "observability-dashboard"
    namespace = local.obs_namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }

  spec {
    selector = {
      app = "observability-dashboard"
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_namespace_v1.observability]
}

################################################################################
# Build & Push Dashboard Image
################################################################################

locals {
  obs_src_dir = "${path.module}/../observability-dashboard"
  obs_src_hash = sha256(join("", [
    filesha256("${local.obs_src_dir}/Dockerfile"),
    filesha256("${local.obs_src_dir}/app.py"),
    filesha256("${local.obs_src_dir}/requirements.txt"),
    filesha256("${local.obs_src_dir}/static/style.css"),
    filesha256("${local.obs_src_dir}/templates/index.html"),
  ]))
}

resource "terraform_data" "observability_dashboard_image" {
  triggers_replace = [local.obs_src_hash]

  provisioner "local-exec" {
    working_dir = local.obs_src_dir
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      export DOCKER_CONFIG=$(mktemp -d)
      trap 'rm -rf "$DOCKER_CONFIG"' EXIT
      TOKEN=$(aws ecr get-login-password --region ${data.aws_region.current.id})
      AUTH=$(printf 'AWS:%s' "$TOKEN" | base64)
      printf '{"auths":{"%s":{"auth":"%s"}}}' \
        "${aws_ecr_repository.observability_dashboard.repository_url}" "$AUTH" \
        > "$DOCKER_CONFIG/config.json"
      for attempt in 1 2 3; do
        if docker buildx build --platform linux/arm64 \
          -t ${aws_ecr_repository.observability_dashboard.repository_url}:latest \
          --push .; then
          exit 0
        fi
        echo "Build attempt $attempt failed; retrying in 15s..." >&2
        sleep 15
      done
      exit 1
    EOT
  }
}

################################################################################
# Outputs
################################################################################

output "observability_dashboard_ecr_url" {
  value       = aws_ecr_repository.observability_dashboard.repository_url
  description = "ECR repository URL for the observability dashboard image"
}

output "observability_dashboard_url" {
  value       = try("http://${kubernetes_service_v1.observability_dashboard.status[0].load_balancer[0].ingress[0].hostname}", "(pending)")
  description = "URL to access the observability dashboard"
}
