locals {
  eks_cluster_name     = local.enable_eks ? module.eks_cluster[0].cluster_name : ""
  eks_cluster_endpoint = local.enable_eks ? module.eks_cluster[0].cluster_endpoint : "https://disabled.invalid"
  eks_cluster_ca_data  = local.enable_eks ? module.eks_cluster[0].cluster_certificate_authority_data : base64encode("disabled")
}

provider "kubernetes" {
  host                   = local.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.eks_cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.enable_eks ? ["eks", "get-token", "--cluster-name", local.eks_cluster_name] : ["sts", "get-caller-identity"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks_cluster_ca_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.enable_eks ? ["eks", "get-token", "--cluster-name", local.eks_cluster_name] : ["sts", "get-caller-identity"]
    }
  }
}
