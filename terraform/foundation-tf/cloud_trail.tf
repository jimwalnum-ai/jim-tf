resource "aws_cloudtrail" "cs" {
  name                          = "cs-cloudtrail"
  s3_bucket_name                = module.s3-cloudtrail.bucket_name
  include_global_service_events = false
}

module "s3-cloudtrail" {
  source        = "../modules/s3"
  bucket_name   = "${local.prefix}-use1-cloud-trail"
  bucket_policy = ""
  kms_key       = module.backend-kms-key.kms_key_arn
  versioning    = "Enabled"
  tags          = local.tags
}

data "aws_iam_policy_document" "cloudtrail" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [module.s3-cloudtrail.bucket_arn]
  }

  statement {
    sid     = "RequireSSL"
    actions = ["s3:*"]
    effect  = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = ["${module.s3-cloudtrail.bucket_arn}"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = [false]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${module.s3-cloudtrail.bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = module.s3-cloudtrail.bucket_name
  policy = data.aws_iam_policy_document.cloudtrail.json
}
