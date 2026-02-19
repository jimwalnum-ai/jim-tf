module "ebs-kms-key" {
  source         = "../modules/kms"
  key_name       = "cs-ebs-kms"
  readonly_roles = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  write_roles    = ["arn:aws:iam::${local.acct_id}:role/cs-terraform-role", "arn:aws:iam::${local.acct_id}:root"]
  tags           = local.tags
}

resource "aws_ebs_encryption_by_default" "default" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "default" {
  key_arn = module.ebs-kms-key.kms_key_arn
}
