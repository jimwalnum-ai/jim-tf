resource "kubernetes_namespace_v1" "app_namespace" {
  metadata {
    name = "flask-app"
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
      }
      spec {
        container {
          name  = "flask-app-container"
          image = "${aws_ecr_repository.flask_app.repository_url}:latest"
          port {
            container_port = 8000
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
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
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

output "app_url" {
  value       = kubernetes_service_v1.flask_app_service.status[0].load_balancer[0].ingress[0].hostname
  description = "The URL to access the deployed Flask application"
}
