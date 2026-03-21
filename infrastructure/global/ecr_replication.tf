################################################################################
# ECR Cross-Region Replication
#
# Replicates ALL ECR repositories from us-east-1 to us-west-2 so that the
# west EKS cluster pulls images from a local registry.
################################################################################

resource "aws_ecr_replication_configuration" "cross_region" {
  replication_configuration {
    rule {
      destination {
        region      = "us-west-2"
        registry_id = data.aws_caller_identity.current.account_id
      }
    }
  }
}
