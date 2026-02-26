resource "kubernetes_namespace_v1" "stress_test_namespace" {
  metadata {
    name = "stress-test"
  }
}

resource "kubernetes_deployment_v1" "stress_test_deployment" {
  metadata {
    name      = "stress-test"
    namespace = kubernetes_namespace_v1.stress_test_namespace.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "stress-test"
      }
    }
    template {
      metadata {
        labels = {
          app = "stress-test"
        }
      }
      spec {
        container {
          name  = "stress-test"
          image = "${aws_ecr_repository.stress_test.repository_url}:latest"
          port {
            container_port = 8080
          }
          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "2048Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "stress_test_service" {
  metadata {
    name      = "stress-test-service"
    namespace = kubernetes_namespace_v1.stress_test_namespace.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  spec {
    selector = {
      app = "stress-test"
    }
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "stress_test_hpa" {
  metadata {
    name      = "stress-test-hpa"
    namespace = kubernetes_namespace_v1.stress_test_namespace.metadata[0].name
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.stress_test_deployment.metadata[0].name
    }
    min_replicas = 1
    max_replicas = 10
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 50
        }
      }
    }
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

output "stress_test_url" {
  value       = kubernetes_service_v1.stress_test_service.status[0].load_balancer[0].ingress[0].hostname
  description = "The public URL to access the stress-test app"
}
