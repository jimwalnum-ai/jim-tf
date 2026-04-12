################################################################################
# NVIDIA Device Plugin DaemonSet (deployed via Helm)
#
# Exposes nvidia.com/gpu as a schedulable Kubernetes resource so that pods
# can request GPU capacity. The DaemonSet tolerates the GPU taint so it runs
# on (and only on) GPU-tainted nodes.
################################################################################

resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.nvidia_device_plugin_version
  namespace  = "kube-system"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      # Tolerate the GPU taint so the DaemonSet schedules on GPU nodes.
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]

      # Pin the DaemonSet to nodes that carry the GPU label.
      nodeSelector = {
        "nvidia.com/gpu" = "true"
      }

      # gfd (GPU Feature Discovery) labels nodes with hardware capabilities,
      # enabling fine-grained scheduling on multi-GPU topologies.
      gfd = {
        enabled = true
      }
    })
  ]

  depends_on = [module.gpu_node_group]
}
