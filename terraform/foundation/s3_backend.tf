module "backend-kms-key" {
  source   = "../modules/kms"
  key_name = "${local.prefix}-use1-backend-s3-kms"
  readonly_roles = ["arn:aws:iam::${local.acct_id}:root",
  "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"]
  write_roles                          = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  autoscaling_service_role_arn_pattern = "arn:aws:iam::${local.acct_id}:role/unused-kms-policy-placeholder"
  eks_node_role_arn_pattern            = ["arn:aws:iam::${local.acct_id}:role/unused-kms-policy-placeholder"]
}

module "s3" {
  source        = "../modules/s3"
  bucket_name   = local.state_bucket_name
  bucket_policy = ""
  kms_key       = module.backend-kms-key.kms_key_arn
  versioning    = "Enabled"
  tags          = local.tags
}

data "template_file" "s3_policy" {
  template = file("./templates/s3_tf_bucket_policy.json.tpl")
  vars = {
    bucket_name = module.s3.bucket_name
    tf_user_arn = "arn:aws:iam::${local.acct_id}:user/cloud_user"
  }
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = module.s3.bucket_name
  policy = data.template_file.s3_policy.rendered
}






