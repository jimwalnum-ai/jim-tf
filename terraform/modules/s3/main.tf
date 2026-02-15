#locals {
#   policy = var.is_flow_log ? data.aws_iam_policy_document.combined.json : var.bucket_policy
#}

resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
  tags   = var.tags
  dynamic "logging" {
    for_each = var.logging_bucket
    content {
      target_bucket = var.logging_bucket
      target_prefix = var.logging_prefix
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "short_bucket" {
  count  = var.life_cycle_term == "short-term" ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  rule {
    status = "Enabled"
    id     = "archive-after-short-term"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = var.versioning
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypt" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = try(var.kms_key, null)
      sse_algorithm     = length(var.kms_key) > 0 ? "aws:kms" : "AES256"
    }
  }
}

# no public access
resource "aws_s3_bucket_public_access_block" "access" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##resource "aws_s3_bucket_policy" "policy"{
#  bucket = aws_s3_bucket.bucket.id
#  policy = data.aws_iam_policy_document.combined.json
#  policy = var.bucket_policy
#}

#data "aws_iam_policy_document" "combined" {
#  source_policy_documents = [
#    data.aws_iam_policy_document.flow_log_s3.json,
#    jsonencode(var.bucket_policy)
#  ]
#}

data "aws_iam_policy_document" "flow_log_s3" {
  statement {
    sid = "AWSLogDeliveryWrite"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.bucket_name}/AWSLogs/*"]
  }
  statement {
    sid = "AWSLogDeliveryAclCheck"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:aws:s3:::${var.bucket_name}"]
  }
}

