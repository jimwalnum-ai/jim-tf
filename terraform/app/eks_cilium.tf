resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.17.4"
  namespace  = "kube-system"

  set {
    name  = "eni.enabled"
    value = "false"
  }

  set {
    name  = "ipam.mode"
    value = "cluster-pool"
  }

  set {
    name  = "ipam.operator.clusterPoolIPv4PodCIDRList"
    value = "10.244.0.0/16"
  }

  set {
    name  = "tunnel"
    value = "vxlan"
  }

  set {
    name  = "routingMode"
    value = "tunnel"
  }

  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }

  set {
    name  = "k8sServiceHost"
    value = trimprefix(module.eks_cluster.cluster_endpoint, "https://")
  }

  set {
    name  = "k8sServicePort"
    value = "443"
  }

  set {
    name  = "egressMasqueradeInterfaces"
    value = "eth+"
  }

  set {
    name  = "hubble.relay.enabled"
    value = "true"
  }

  set {
    name  = "hubble.ui.enabled"
    value = "true"
  }

  depends_on = [module.eks_cluster]
}
