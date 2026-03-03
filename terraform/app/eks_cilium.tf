resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.19.1"
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  set = [
    { name = "eni.enabled", value = "false" },
    { name = "ipam.mode", value = "cluster-pool" },
    { name = "ipam.operator.clusterPoolIPv4PodCIDRList", value = "10.244.0.0/16" },
    { name = "routingMode", value = "tunnel" },
    { name = "tunnelProtocol", value = "vxlan" },
    { name = "kubeProxyReplacement", value = "true" },
    { name = "k8sServiceHost", value = trimprefix(module.eks_cluster.cluster_endpoint, "https://") },
    { name = "k8sServicePort", value = "443" },
    { name = "bpf.masquerade", value = "true" },
    { name = "enableIPv4Masquerade", value = "true" },
    { name = "bpf.datapathMode", value = "veth" },
    { name = "cni.exclusive", value = "true" },
    { name = "devices", value = "ens+" },
    { name = "nodeinit.enabled", value = "true" },
    { name = "operator.replicas", value = "1" },
    { name = "hubble.relay.enabled", value = "true" },
    { name = "hubble.ui.enabled", value = "true" },
  ]

  depends_on = [module.eks_cluster]
}
