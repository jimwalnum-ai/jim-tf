module "tgw" {
  source = "../modules/transit-gateway"
  env = "dev"
  tags = local.tags
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "core-kms-key" {
  source = "../modules/kms"
  key_name = "cs-core-kms"
  readonly_roles = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  write_roles = ["arn:aws:iam::${local.acct_id}:role/cs-terraform-role","arn:aws:iam::${local.acct_id}:root"]
  tags = local.tags
}

module "s3-flow-log-bucket" {
  source = "../modules/s3"
  bucket_name = "cs-use1-vpc-flow-logs"
  bucket_policy = ""
  kms_key = module.core-kms-key.kms_key_arn
  is_flow_log = true
  life_cycle_term = "short-term"   
  tags = local.tags
}

module "vpc-dev" {
  source = "../modules/vpc"
  ipv4_ipam_pool_id  = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length = 22
  name   = "cs-basics"
  env    = "dev"
  region = "us-east-1"
  private_subnets_count = 3
  public_subnets_count = 1
  transit_gateway = module.tgw.id
  test = true
  flow_log_bucket = module.s3-flow-log-bucket.bucket_arn
  endpoint_access_role = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
  tags = local.tags
  depends_on = [module.s3-flow-log-bucket,module.tgw,aws_vpc_ipam.cs-main]
}

module "vpc-prd" {
  source = "../modules/vpc"
  ipv4_ipam_pool_id  = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length = 22
  name   = "cs-basics"
  env    = "prd"
  region = "us-east-1"
  private_subnets_count = 3
  transit_gateway = module.tgw.id
  flow_log_bucket = module.s3-flow-log-bucket.bucket_arn
  endpoint_access_role = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
  tags = local.tags
  depends_on = [module.s3-flow-log-bucket,module.tgw,aws_vpc_ipam.cs-main]
}

# Inspection vpc for Network firewall 
module "vpc-inspect" {
  source = "../modules/inspect-vpc"
  ipv4_ipam_pool_id  = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length = 22
  name   = "cs-basics"
  env    = "inspect"
  region = "us-east-1"
  flow_log_bucket = module.s3-flow-log-bucket.bucket_arn
  transit_gateway = module.tgw.id
  super_cidr_block  = "10.0.0.0/18"
  tags = local.tags
  depends_on = [aws_vpc_ipam.cs-main,module.tgw]
}

locals {
firewall_sync_states = aws_networkfirewall_firewall.inspection_vpc_fw.firewall_status[0].sync_states
}

resource "aws_route_table" "inspection_vpc_public_subnet_route_table" {
  count  = 2
  vpc_id = module.vpc-inspect.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = module.vpc-inspect.igw_id
  }
  route {
    cidr_block = "10.0.0.0/18"
    vpc_endpoint_id = element([for ss in local.firewall_sync_states : ss.attachment[0].endpoint_id if ss.attachment[0].subnet_id == module.vpc-inspect.firewall_subnets[count.index].id], 0)
  }
  tags = {
    Name = "inspection-vpc/${data.aws_availability_zones.available.names[count.index]}/public-subnet-route-table"
  }
}

resource "aws_route_table_association" "inspection_vpc_public_subnet_route_table_association" {
  count          = 2
  route_table_id = aws_route_table.inspection_vpc_public_subnet_route_table[count.index].id
  subnet_id      = module.vpc-inspect.public_subnets[count.index].id
}

resource "aws_route_table" "inspection_vpc_tgw_subnet_route_table" {
  count  = 2
  vpc_id = module.vpc-inspect.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    vpc_endpoint_id = element([for ss in local.firewall_sync_states : ss.attachment[0].endpoint_id if ss.attachment[0].subnet_id == module.vpc-inspect.firewall_subnets[count.index].id], 0)
  }
  tags = {
    Name = "inspection-vpc/${data.aws_availability_zones.available.names[count.index]}/tgw-subnet-route-table"
  }
}

resource "aws_route_table_association" "inspection_vpc_tgw_subnet_route_table_association" {
  count          = 2
  route_table_id = aws_route_table.inspection_vpc_tgw_subnet_route_table[count.index].id
  subnet_id      = module.vpc-inspect.firewall_subnets[count.index].id
}


# Creates route tables between VPC's, tgw and inspection vpc
module "tgw-route-tables" {
  source = "../modules/tgw-route-tables"
  tgw_id = module.tgw.id
  inspection_vpc_id = module.vpc-inspect.vpc_id
  inspection_tgw_subnets = module.vpc-inspect.tgw_subnets.*.id
  spoke_subnets = concat(module.vpc-dev.tgw_subnets,module.vpc-prd.tgw_subnets)
  spoke_vpc_ids = concat(module.vpc-dev.vpc_list,module.vpc-prd.vpc_list)
  depends_on = [module.vpc-inspect,module.vpc-dev,module.vpc-prd,module.tgw]
}

#resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_tgw_attachment" {
# for_each = concat(module.vpc-dev.tgw_subnets,module.vpc-prd.tgw_subnets)
#  subnet_ids                                      = each.value
#  transit_gateway_id                              = module.tgw.id
#  vpc_id                                          = each.key
#  transit_gateway_default_route_table_association = false
#  tags = {
#    Name = "spoke-each.value-attachment"
#  }
#}
