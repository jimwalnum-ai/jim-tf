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
    { name = "hubble.export.static.enabled", value = "true" },
    { name = "hubble.export.static.filePath", value = "/var/run/cilium/hubble/events.log" },
    { name = "hubble.export.static.fieldMask[0]", value = "source.namespace" },
    { name = "hubble.export.static.fieldMask[1]", value = "source.pod_name" },
    { name = "hubble.export.static.fieldMask[2]", value = "destination.namespace" },
    { name = "hubble.export.static.fieldMask[3]", value = "destination.pod_name" },
    { name = "hubble.export.static.fieldMask[4]", value = "verdict" },
    { name = "hubble.export.static.fieldMask[5]", value = "IP" },
    { name = "hubble.export.static.fieldMask[6]", value = "l4" },
    { name = "hubble.export.static.fieldMask[7]", value = "l7" },
    { name = "hubble.export.fileMaxSizeMB", value = "10" },
    { name = "hubble.export.fileMaxBackups", value = "5" },
  ]

  depends_on = [module.eks_cluster]
}
