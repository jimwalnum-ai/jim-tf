data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  available_azs = sort(data.aws_availability_zones.available.names)
}

module "core-kms-key" {
  source                               = "../modules/kms"
  key_name                             = "cs-core-kms-west"
  readonly_roles                       = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  write_roles                          = ["arn:aws:iam::${local.acct_id}:role/cs-terraform-role", "arn:aws:iam::${local.acct_id}:root"]
  autoscaling_service_role_arn_pattern = "arn:aws:iam::${local.acct_id}:role/unused-kms-policy-placeholder"
  eks_node_role_arn_pattern            = ["arn:aws:iam::${local.acct_id}:role/unused-kms-policy-placeholder"]
  tags                                 = local.tags
}

module "s3-flow-log-bucket" {
  source          = "../modules/s3"
  bucket_name     = "${local.prefix}-usw2-vpc-flow-logs-1"
  bucket_policy   = ""
  kms_key         = module.core-kms-key.kms_key_arn
  is_flow_log     = true
  life_cycle_term = "short-term"
  tags            = local.tags
}

module "vpc" {
  for_each               = local.spoke_vpcs
  source                 = "../modules/vpc"
  ipv4_ipam_pool_id      = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length    = each.value.ipv4_netmask_length
  name                   = local.vpc_name
  env                    = each.value.env
  region                 = each.value.region
  private_subnets_count  = each.value.private_subnets_count
  public_subnets_count   = each.value.public_subnets_count
  availability_zones     = slice(local.available_azs, 0, max(each.value.private_subnets_count, each.value.public_subnets_count))
  transit_gateway        = ""
  create_tgw_routes      = each.value.create_tgw_routes
  test                   = each.value.test
  flow_log_bucket        = module.s3-flow-log-bucket.bucket_arn
  endpoint_access_role   = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
  public_ingress_cidrs   = [chomp(file("../../ip.txt"))]
  internal_ingress_cidrs = local.internal_ingress_cidrs
  tgw_subnet_tags        = each.value.tgw_subnet_tags
  use_transit_gateway    = local.use_transit_gateway
  tags                   = local.tags
  depends_on             = [module.s3-flow-log-bucket, aws_vpc_ipam.cs-west]
}
