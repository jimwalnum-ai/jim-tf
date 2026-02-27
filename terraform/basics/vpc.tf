module "tgw" {
  source          = "../modules/transit-gateway"
  env             = "dev"
  flow_log_bucket = module.s3-flow-log-bucket.bucket_arn
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  available_azs = sort(data.aws_availability_zones.available.names)
}

module "core-kms-key" {
  source                               = "../modules/kms"
  key_name                             = "cs-core-kms"
  readonly_roles                       = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  write_roles                          = ["arn:aws:iam::${local.acct_id}:role/cs-terraform-role", "arn:aws:iam::${local.acct_id}:root"]
  autoscaling_service_role_arn_pattern = "arn:aws:iam::${local.acct_id}:role/unused-kms-policy-placeholder"
  eks_node_role_arn_pattern            = ["arn:aws:iam::${local.acct_id}:role/unused-kms-policy-placeholder"]
  tags                                 = local.tags
}

module "s3-flow-log-bucket" {
  source          = "../modules/s3"
  bucket_name     = "${local.prefix}-use1-vpc-flow-logs-1"
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
  transit_gateway        = module.tgw.id
  create_tgw_routes      = each.value.create_tgw_routes
  test                   = each.value.test
  flow_log_bucket        = module.s3-flow-log-bucket.bucket_arn
  endpoint_access_role   = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
  public_ingress_cidrs   = [chomp(file("../../ip.txt"))]
  internal_ingress_cidrs = local.internal_ingress_cidrs
  tgw_subnet_tags        = each.value.tgw_subnet_tags
  tags                   = local.tags
  depends_on             = [module.s3-flow-log-bucket, module.tgw, aws_vpc_ipam.cs-main]
}

#module "vpc-egress" {
#  source = "../modules/transit-egress-vpc"
#  ipv4_ipam_pool_id  = aws_vpc_ipam_pool.regional.id
#  ipv4_netmask_length = 24
#  name   = "cs-basics"
#  env    = "egress"
#  region = "us-east-1"
#  vpc_attach_cidrs = [module.vpc-dev.vpc_cidr, module.vpc-prd.vpc_cidr]
#  flow_log_bucket = module.s3-flow-log-bucket.bucket_arn
#  transit_gateway = module.tgw.id
#  firewall_endpoint = element(flatten(resource.aws_networkfirewall_firewall.inspection_vpc_fw.firewall_status[0].sync_states[*].attachment[*].endpoint_id),0)
#  tags = local.tags
#  depends_on = [module.vpc-dev,module.vpc-prd,module.s3-flow-log-bucket,aws_vpc_ipam.cs-main]
#}

# Inspection vpc for Network firewall 
module "vpc-inspect" {
  source                 = "../modules/inspect-vpc"
  ipv4_ipam_pool_id      = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length    = local.inspect_vpc.ipv4_netmask_length
  tgw_subnet_cidr_offset = local.inspect_vpc.tgw_subnet_cidr_offset
  name                   = local.vpc_name
  env                    = local.inspect_vpc.env
  region                 = local.inspect_vpc.region
  availability_zones     = local.available_azs
  flow_log_bucket        = module.s3-flow-log-bucket.bucket_arn
  transit_gateway        = module.tgw.id
  super_cidr_block       = local.inspect_vpc.super_cidr_block
  public_ingress_cidrs   = [chomp(file("../../ip.txt"))]
  internal_ingress_cidrs = local.internal_ingress_cidrs
  tags                   = local.tags
  depends_on             = [module.vpc, module.s3-flow-log-bucket, aws_vpc_ipam.cs-main]
}

resource "aws_route_table" "inspection_vpc_tgw_subnet_route_table" {
  count  = 2
  vpc_id = module.vpc-inspect.vpc_id
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = element([for ss in aws_networkfirewall_firewall.inspection_vpc_fw.firewall_status[0].sync_states : ss.attachment[0].endpoint_id if ss.attachment[0].subnet_id == module.vpc-inspect.firewall_subnets[count.index].id], 0)
  }
  tags = {
    Name = "inspection-vpc/${local.available_azs[count.index]}/tgw-subnet-route-table"
  }
  depends_on = [aws_networkfirewall_firewall.inspection_vpc_fw]
}

resource "aws_route_table_association" "inspection_vpc_tgw_subnet_route_table_association" {
  count          = 2
  route_table_id = aws_route_table.inspection_vpc_tgw_subnet_route_table[count.index].id
  subnet_id      = module.vpc-inspect.tgw_subnets[count.index].id
}

resource "aws_route_table" "inspection_vpc_firewall_subnet_route_table" {
  count  = 2
  vpc_id = module.vpc-inspect.vpc_id
  route {
    cidr_block         = local.tgw_cidr_block
    transit_gateway_id = module.tgw.id
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = module.vpc-inspect.nat_gateways[count.index].id
  }
  tags = {
    Name = "inspection-vpc/${local.available_azs[count.index]}/firewall-subnet-route-table"
  }
}

resource "aws_route_table_association" "inspection_vpc_firewall_subnet_route_table_association" {
  count          = 2
  route_table_id = aws_route_table.inspection_vpc_firewall_subnet_route_table[count.index].id
  subnet_id      = module.vpc-inspect.firewall_subnets[count.index].id
}

resource "aws_route_table" "inspection_vpc_public_subnet_route_table" {
  count  = 2
  vpc_id = module.vpc-inspect.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = module.vpc-inspect.igw_id
  }
  route {
    cidr_block      = local.tgw_cidr_block
    vpc_endpoint_id = element([for ss in aws_networkfirewall_firewall.inspection_vpc_fw.firewall_status[0].sync_states : ss.attachment[0].endpoint_id if ss.attachment[0].subnet_id == module.vpc-inspect.firewall_subnets[count.index].id], 0)
  }

  tags = {
    Name = "inspection-vpc/${local.available_azs[count.index]}/public-subnet-route-table"
  }
  depends_on = [aws_networkfirewall_firewall.inspection_vpc_fw]
}

resource "aws_route_table_association" "inspection_vpc_public_subnet_route_table_association" {
  count          = 2
  route_table_id = aws_route_table.inspection_vpc_public_subnet_route_table[count.index].id
  subnet_id      = module.vpc-inspect.public_subnets[count.index].id
}


resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  for_each                                        = local.spoke_vpcs
  subnet_ids                                      = module.vpc[each.key].tgw_subnets
  transit_gateway_id                              = module.tgw.id
  vpc_id                                          = module.vpc[each.key].vpc_id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  depends_on                                      = [module.tgw]
  tags                                            = local.tags
}

#resource "aws_ec2_transit_gateway_vpc_attachment" "vpc-egress" {
#  subnet_ids         = module.vpc-egress.private_subnets.*.id
#  transit_gateway_id = module.tgw.id
#  vpc_id            = module.vpc-egress.vpc_id
#  depends_on = [module.tgw]
#  tags = local.tags
#}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc-inspect" {
  subnet_ids                                      = module.vpc-inspect.tgw_subnets.*.id
  transit_gateway_id                              = module.tgw.id
  vpc_id                                          = module.vpc-inspect.vpc_id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  appliance_mode_support                          = "enable"
  depends_on                                      = [module.tgw]
  tags                                            = local.tags
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  for_each           = local.spoke_vpcs
  transit_gateway_id = module.tgw.id
  tags               = merge(local.tags, { Name = "cs-tgw-${each.key}-route-table" })
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each                       = local.spoke_vpcs
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}

resource "aws_ec2_transit_gateway_route_table_association" "vpc_inspect_association" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc-inspect.id
  transit_gateway_route_table_id = module.tgw.inspection_route_table.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_to_inspect" {
  for_each                       = local.spoke_vpcs
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke[each.key].id
  transit_gateway_route_table_id = module.tgw.inspection_route_table.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "inspect_to_spoke" {
  for_each                       = local.spoke_vpcs
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc-inspect.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}

resource "aws_ec2_transit_gateway_route" "spoke_internet" {
  for_each                       = local.spoke_vpcs
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc-inspect.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
  depends_on                     = [module.tgw]
}

resource "aws_ec2_transit_gateway_route" "blackhole" {
  for_each                       = local.blackhole_pairs
  destination_cidr_block         = module.vpc[each.value.dst_key].vpc_cidr
  blackhole                      = true
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.value.src_key].id
}


