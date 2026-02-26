# The EKS module creates the OIDC provider using the new API domain format
# (oidc-eks.us-east-1.api.aws), but the cluster issues tokens with the legacy
# domain (oidc.eks.us-east-1.amazonaws.com). IRSA fails because STS can't
# match the token issuer to the provider. This creates a provider that matches
# the actual cluster issuer URL.
data "tls_certificate" "eks_legacy" {
  url = module.eks_cluster.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks_legacy_oidc" {
  url             = module.eks_cluster.cluster_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_legacy.certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name = "${module.eks_cluster.cluster_name}-irsa-legacy-domain"
  })
}
