################################################################################
# Namespace
################################################################################

resource "kubernetes_namespace_v1" "monitoring" {
  count = local.enable_eks ? 1 : 0

  metadata {
    name = "monitoring"
  }

  depends_on = [module.eks_node_group]
}

################################################################################
# kube-prometheus-stack
#
# Deploys Prometheus, Alertmanager, and Grafana via the community Helm chart.
# Prometheus scrapes kube-state-metrics, node-exporter, and any workload pods
# annotated with prometheus.io/scrape=true.  Grafana ships pre-built dashboards
# for cluster health, node utilisation, and workload golden-signals.
################################################################################

resource "helm_release" "kube_prometheus_stack" {
  count      = local.enable_eks ? 1 : 0
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring[0].metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "69.3.2"

  wait    = true
  timeout = 600

  set = [
    # Reduce replica count to stay within sandbox resource limits
    { name = "prometheus.prometheusSpec.replicas", value = "1" },
    { name = "alertmanager.alertmanagerSpec.replicas", value = "1" },
    { name = "grafana.replicas", value = "1" },

    # Retention: 15 days of metrics in a sandbox-sized PVC
    { name = "prometheus.prometheusSpec.retention", value = "15d" },
    { name = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage", value = "20Gi" },

    # Scrape every workload pod annotated with prometheus.io/scrape=true
    { name = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues", value = "false" },
    { name = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues", value = "false" },

    # Grafana admin password (override in production via a sealed secret)
    { name = "grafana.adminPassword", value = "changeme" },

    # Expose Grafana via an internal NLB so it is reachable within the VPC
    { name = "grafana.service.type", value = "LoadBalancer" },
    { name = "grafana.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type", value = "nlb" },
    { name = "grafana.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme", value = "internal" },

    # Ship default Kubernetes / node dashboards
    { name = "grafana.defaultDashboardsEnabled", value = "true" },

    # Resource requests sized for t3.medium sandbox nodes
    { name = "prometheus.prometheusSpec.resources.requests.cpu", value = "200m" },
    { name = "prometheus.prometheusSpec.resources.requests.memory", value = "512Mi" },
    { name = "prometheus.prometheusSpec.resources.limits.cpu", value = "500m" },
    { name = "prometheus.prometheusSpec.resources.limits.memory", value = "1Gi" },
    { name = "grafana.resources.requests.cpu", value = "100m" },
    { name = "grafana.resources.requests.memory", value = "128Mi" },
    { name = "grafana.resources.limits.cpu", value = "200m" },
    { name = "grafana.resources.limits.memory", value = "256Mi" },
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

################################################################################
# Output
################################################################################

output "grafana_service_name" {
  value       = local.enable_eks ? "kube-prometheus-stack-grafana.monitoring.svc.cluster.local" : "(EKS disabled)"
  description = "In-cluster DNS name for the Grafana service"
}
