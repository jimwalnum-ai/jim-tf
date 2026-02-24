module "ebs-kms-key" {
  source                               = "../modules/kms"
  key_name                             = "cs-ebs-kms"
  readonly_roles                       = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  write_roles                          = ["arn:aws:iam::${local.acct_id}:role/cs-terraform-role", "arn:aws:iam::${local.acct_id}:root"]
  autoscaling_service_role_arn_pattern = "arn:aws:iam::${local.acct_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
  eks_node_role_arn_pattern = [
    "arn:aws:iam::${local.acct_id}:role/general_purpose-eks-node-group-*",
    "arn:aws:iam::${local.acct_id}:role/eks-node-group-role"
  ]
  tags = local.tags
}

module "ebs-kms-key-v2" {
  source                               = "../modules/kms"
  key_name                             = "cs-ebs-kms-v2"
  readonly_roles                       = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  write_roles                          = ["arn:aws:iam::${local.acct_id}:role/cs-terraform-role", "arn:aws:iam::${local.acct_id}:root"]
  autoscaling_service_role_arn_pattern = "arn:aws:iam::${local.acct_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
  eks_node_role_arn_pattern = [
    "arn:aws:iam::${local.acct_id}:role/general_purpose-eks-node-group-*",
    "arn:aws:iam::${local.acct_id}:role/eks-node-group-role"
  ]
  tags = local.tags
}

resource "aws_ebs_encryption_by_default" "default" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "default" {
  key_arn = module.ebs-kms-key-v2.kms_key_arn
}
