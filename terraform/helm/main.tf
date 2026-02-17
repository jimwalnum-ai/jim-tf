terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.1"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

provider "kubernetes" {
  config_path            = var.eks_cluster_name == null ? var.kubeconfig_path : null
  config_context         = var.eks_cluster_name == null ? var.kubeconfig_context : null
  host                   = var.eks_cluster_name == null ? null : data.aws_eks_cluster.cluster[0].endpoint
  cluster_ca_certificate = var.eks_cluster_name == null ? null : base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data)
  token                  = var.eks_cluster_name == null ? null : data.aws_eks_cluster_auth.cluster[0].token
}

provider "helm" {
  kubernetes = {
    config_path            = var.eks_cluster_name == null ? var.kubeconfig_path : null
    config_context         = var.eks_cluster_name == null ? var.kubeconfig_context : null
    host                   = var.eks_cluster_name == null ? null : data.aws_eks_cluster.cluster[0].endpoint
    cluster_ca_certificate = var.eks_cluster_name == null ? null : base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data)
    token                  = var.eks_cluster_name == null ? null : data.aws_eks_cluster_auth.cluster[0].token
  }
}

data "aws_eks_cluster" "cluster" {
  count = var.eks_cluster_name == null ? 0 : 1
  name  = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  count = var.eks_cluster_name == null ? 0 : 1
  name  = var.eks_cluster_name
}

locals {
  chart_path = coalesce(var.chart_path, "${path.module}/../code/helm/factor-workloads")
}

resource "kubernetes_namespace_v1" "workloads" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "factor_workloads" {
  name             = var.release_name
  namespace        = kubernetes_namespace_v1.workloads.metadata[0].name
  chart            = local.chart_path
  create_namespace = false
  values           = [yamlencode(var.values)]
}
