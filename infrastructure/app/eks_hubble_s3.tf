################################################################################
# S3 Bucket for Hubble Flow Logs
################################################################################

module "hubble_logs_bucket" {
  source = "../modules/s3"

  bucket_name     = "${local.prefix}-hubble-flow-logs"
  life_cycle_term = "short-term"
  tags            = local.tags
}

################################################################################
# IRSA for Fluent Bit → S3
################################################################################

locals {
  fluent_bit_namespace = "fluent-bit"
  fluent_bit_sa_name   = "fluent-bit"
}

resource "aws_iam_policy" "fluent_bit_s3" {
  name        = "${module.eks_cluster.cluster_name}-fluent-bit-s3"
  description = "Allow Fluent Bit to write Hubble flow logs to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3PutHubbleLogs"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket",
        ]
        Resource = [
          module.hubble_logs_bucket.bucket_arn,
          "${module.hubble_logs_bucket.bucket_arn}/*",
        ]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role" "fluent_bit" {
  name = "${module.eks_cluster.cluster_name}-fluent-bit"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks_cluster.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks_cluster.oidc_provider}:aud" = "sts.amazonaws.com"
            "${module.eks_cluster.oidc_provider}:sub" = "system:serviceaccount:${local.fluent_bit_namespace}:${local.fluent_bit_sa_name}"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "fluent_bit_s3" {
  role       = aws_iam_role.fluent_bit.name
  policy_arn = aws_iam_policy.fluent_bit_s3.arn
}

################################################################################
# Fluent Bit Namespace
################################################################################

resource "kubernetes_namespace" "fluent_bit" {
  metadata {
    name = local.fluent_bit_namespace
  }

  depends_on = [module.eks_node_group]
}

################################################################################
# Fluent Bit — tail Hubble export file, ship to S3
################################################################################

resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = local.fluent_bit_namespace

  wait    = true
  timeout = 600

  values = [<<-YAML
    serviceAccount:
      create: true
      name: "${local.fluent_bit_sa_name}"
      annotations:
        eks.amazonaws.com/role-arn: "${aws_iam_role.fluent_bit.arn}"

    config:
      service: |
        [SERVICE]
            Flush         5
            Log_Level     info
            Daemon        off
            HTTP_Server   On
            HTTP_Listen   0.0.0.0
            HTTP_Port     2020
            Parsers_File  /fluent-bit/etc/parsers.conf

      inputs: |
        [INPUT]
            Name              tail
            Tag               hubble.flows
            Path              /var/run/cilium/hubble/events.log
            Parser            json
            Refresh_Interval  5
            Rotate_Wait       30
            DB                /var/log/flb_hubble.db

      outputs: |
        [OUTPUT]
            Name                         s3
            Match                        hubble.*
            bucket                       ${module.hubble_logs_bucket.bucket_name}
            region                       ${data.aws_region.current.id}
            total_file_size              50M
            upload_timeout               10m
            s3_key_format                /hubble/logs/$$TAG/%Y/%m/%d/%H/$$UUID.gz
            compression                  gzip
            content_type                 application/gzip

      filters: |
        [FILTER]
            Name   modify
            Match  hubble.*
            Add    cluster ${module.eks_cluster.cluster_name}

    extraVolumeMounts:
      - name: cilium-hubble
        mountPath: /var/run/cilium/hubble
        readOnly: true

    extraVolumes:
      - name: cilium-hubble
        hostPath:
          path: /var/run/cilium/hubble
          type: DirectoryOrCreate

    tolerations:
      - operator: Exists
  YAML
  ]

  depends_on = [
    kubernetes_namespace.fluent_bit,
    aws_iam_role_policy_attachment.fluent_bit_s3,
    helm_release.cilium,
  ]
}
