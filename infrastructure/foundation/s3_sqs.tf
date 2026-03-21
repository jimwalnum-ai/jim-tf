#module "backend-kms-key" {
#  source = "../modules/kms"
#  key_name = "cs-backend-s3-kms"
#  readonly_roles = ["arn:aws:iam::${local.acct_id}:user/cloud_user",
#                    "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"]
#  write_roles = ["arn:aws:iam::${local.acct_id}:root"]
#  acct_id = local.acct_id
#}

module "s3-sqs" {
  source          = "../modules/s3"
  bucket_name     = "${local.prefix}-use1-sqs-data-bucket-1"
  bucket_policy   = ""
  kms_key         = module.core-kms-key.kms_key_arn
  versioning      = "Enabled"
  life_cycle_term = "short-term"
  tags            = local.tags
}

data "template_file" "s3_sqs_policy" {
  template = file("./templates/s3_sqs_bucket_policy.json.tpl")
  vars = {
    bucket_name = module.s3-sqs.bucket_name
    tf_user_arn = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
  }
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = module.s3-sqs.bucket_name
  policy = data.template_file.s3_sqs_policy.rendered
}





