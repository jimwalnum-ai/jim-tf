resource "kubernetes_namespace_v1" "app_namespace" {
  metadata {
    name = "flask-app"
  }
}

resource "kubernetes_secret_v1" "flask_app_db" {
  metadata {
    name      = "flask-app-db-credentials"
    namespace = kubernetes_namespace_v1.app_namespace.metadata[0].name
  }
  data = {
    password = random_password.master_password.result
  }
}

resource "kubernetes_deployment_v1" "flask_app_deployment" {
  metadata {
    name      = "flask-app-deployment"
    namespace = kubernetes_namespace_v1.app_namespace.metadata[0].name
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "flask-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "flask-app"
        }
        annotations = {
          "src-hash" = local.web_src_hash
        }
      }
      spec {
        container {
          name  = "flask-app-container"
          image = "${aws_ecr_repository.flask_app.repository_url}:latest"
          port {
            container_port = 8000
          }
          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
          }
          env {
            name  = "FACTOR_DB_HOST"
            value = aws_db_instance.factor.address
          }
          env {
            name  = "FACTOR_DB_PORT"
            value = tostring(aws_db_instance.factor.port)
          }
          env {
            name  = "FACTOR_DB_NAME"
            value = var.web_db_name
          }
          env {
            name  = "FACTOR_DB_USER"
            value = aws_db_instance.factor.username
          }
          env {
            name = "FACTOR_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.flask_app_db.metadata[0].name
                key  = "password"
              }
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            failure_threshold     = 3
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "flask_app_service" {
  metadata {
    name      = "flask-app-service"
    namespace = kubernetes_namespace_v1.app_namespace.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  spec {
    selector = {
      app = "flask-app"
    }
    port {
      port        = 80
      target_port = 8000
      protocol    = "TCP"
    }
    type = "LoadBalancer" # Use LoadBalancer to expose the service via an ALB
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "flask_app_hpa" {
  metadata {
    name      = "flask-app-hpa"
    namespace = kubernetes_namespace_v1.app_namespace.metadata[0].name
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.flask_app_deployment.metadata[0].name
    }
    min_replicas = 2
    max_replicas = 10
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 60
        }
      }
    }
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 75
        }
      }
    }
  }
}

output "app_url" {
  value       = kubernetes_service_v1.flask_app_service.status[0].load_balancer[0].ingress[0].hostname
  description = "The URL to access the deployed Flask application"
}
