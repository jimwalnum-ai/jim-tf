module "aurora" {
  for_each = local.enable_aurora ? { for k, v in local.spoke_vpcs : k => v if v.env != "prd" } : {}
  source   = "../modules/aurora"

  name           = "cs-aurora"
  env            = each.value.env
  instance_class = each.value.env == "prd" ? "db.r8g.large" : "db.t3.medium"
  instance_count = each.value.env == "prd" ? 2 : 1

  subnet_ids                 = module.vpc[each.key].protected_subnets
  vpc_id                     = module.vpc[each.key].vpc_id
  allowed_cidr_blocks        = [module.vpc[each.key].vpc_cidr]
  allowed_security_group_ids = []

  database_name   = "appdb"
  master_username = "dbadmin"

  kms_key_arn             = module.core-kms-key.kms_key_arn
  deletion_protection     = each.value.env == "prd"
  backup_retention_period = each.value.env == "prd" ? 14 : 7
  apply_immediately       = each.value.env != "prd"

  tags = local.tags
}
