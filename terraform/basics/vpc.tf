module "tgw" {
  source = "../modules/transit-gateway"
  env    = "dev"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "core-kms-key" {
  source         = "../modules/kms"
  key_name       = "cs-core-kms"
  readonly_roles = ["arn:aws:iam::${local.acct_id}:user/cloud_user"]
  write_roles    = ["arn:aws:iam::${local.acct_id}:role/cs-terraform-role", "arn:aws:iam::${local.acct_id}:root"]
  tags           = local.tags
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

module "vpc-dev" {
  source                 = "../modules/vpc"
  ipv4_ipam_pool_id      = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length    = 22
  name                   = "cs-basics"
  env                    = "dev"
  region                 = "us-east-1"
  private_subnets_count  = 3
  public_subnets_count   = 1
  transit_gateway        = module.tgw.id
  test                   = true
  flow_log_bucket        = module.s3-flow-log-bucket.bucket_arn
  endpoint_access_role   = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
  public_ingress_cidrs   = [chomp(file("../../ip.txt"))]
  internal_ingress_cidrs = ["10.0.0.0/8"]
  tgw_subnet_tags = {
    "kubernetes.io/cluster/eks-cluster-dev" = "shared"
    "kubernetes.io/role/internal-elb"       = "1"
  }
  tags       = local.tags
  depends_on = [module.s3-flow-log-bucket, module.tgw, aws_vpc_ipam.cs-main]
}

module "vpc-prd" {
  source                 = "../modules/vpc"
  ipv4_ipam_pool_id      = aws_vpc_ipam_pool.regional.id
  ipv4_netmask_length    = 22
  name                   = "cs-basics"
  env                    = "prd"
  region                 = "us-east-1"
  private_subnets_count  = 3
  transit_gateway        = module.tgw.id
  flow_log_bucket        = module.s3-flow-log-bucket.bucket_arn
  endpoint_access_role   = "arn:aws:iam::${local.acct_id}:role/cs-terraform-role"
  public_ingress_cidrs   = [chomp(file("../../ip.txt"))]
  internal_ingress_cidrs = ["10.0.0.0/8"]
  tgw_subnet_tags = {
    "kubernetes.io/cluster/eks-cluster-prd" = "shared"
    "kubernetes.io/role/internal-elb"       = "1"
  }
  tags       = local.tags
  depends_on = [module.s3-flow-log-bucket, module.tgw, aws_vpc_ipam.cs-main]
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
  ipv4_netmask_length    = 22
  tgw_subnet_cidr_offset = 6
  name                   = "cs-basics"
  env                    = "inspect"
  region                 = "us-east-1"
  flow_log_bucket        = module.s3-flow-log-bucket.bucket_arn
  transit_gateway        = module.tgw.id
  super_cidr_block       = "10.0.0.0/18"
  public_ingress_cidrs   = [chomp(file("../../ip.txt"))]
  internal_ingress_cidrs = ["10.0.0.0/8"]
  tags                   = local.tags
  depends_on             = [module.vpc-dev, module.vpc-prd, module.s3-flow-log-bucket, aws_vpc_ipam.cs-main]
}

resource "aws_route_table" "inspection_vpc_tgw_subnet_route_table" {
  count  = 2
  vpc_id = module.vpc-inspect.vpc_id
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = element([for ss in aws_networkfirewall_firewall.inspection_vpc_fw.firewall_status[0].sync_states : ss.attachment[0].endpoint_id if ss.attachment[0].subnet_id == module.vpc-inspect.firewall_subnets[count.index].id], 0)
  }
  tags = {
    Name = "inspection-vpc/${data.aws_availability_zones.available.names[count.index]}/tgw-subnet-route-table"
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
    cidr_block         = "10.0.0.0/16"
    transit_gateway_id = module.tgw.id
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = module.vpc-inspect.nat_gateways[count.index].id
  }
  tags = {
    Name = "inspection-vpc/${data.aws_availability_zones.available.names[count.index]}/firewall-subnet-route-table"
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
    cidr_block      = "10.0.0.0/16"
    vpc_endpoint_id = element([for ss in aws_networkfirewall_firewall.inspection_vpc_fw.firewall_status[0].sync_states : ss.attachment[0].endpoint_id if ss.attachment[0].subnet_id == module.vpc-inspect.firewall_subnets[count.index].id], 0)
  }

  tags = {
    Name = "inspection-vpc/${data.aws_availability_zones.available.names[count.index]}/public-subnet-route-table"
  }
  depends_on = [aws_networkfirewall_firewall.inspection_vpc_fw]
}

resource "aws_route_table_association" "inspection_vpc_public_subnet_route_table_association" {
  count          = 2
  route_table_id = aws_route_table.inspection_vpc_public_subnet_route_table[count.index].id
  subnet_id      = module.vpc-inspect.public_subnets[count.index].id
}


resource "aws_ec2_transit_gateway_vpc_attachment" "vpc-dev" {
  subnet_ids         = module.vpc-dev.tgw_subnets
  transit_gateway_id = module.tgw.id
  vpc_id             = module.vpc-dev.vpc_id
  depends_on         = [module.tgw]
  tags               = local.tags
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc-prd" {
  subnet_ids         = module.vpc-prd.tgw_subnets
  transit_gateway_id = module.tgw.id
  vpc_id             = module.vpc-prd.vpc_id
  depends_on         = [module.tgw]
  tags               = local.tags
}

#resource "aws_ec2_transit_gateway_vpc_attachment" "vpc-egress" {
#  subnet_ids         = module.vpc-egress.private_subnets.*.id
#  transit_gateway_id = module.tgw.id
#  vpc_id            = module.vpc-egress.vpc_id
#  depends_on = [module.tgw]
#  tags = local.tags
#}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc-inspect" {
  subnet_ids         = module.vpc-inspect.tgw_subnets.*.id
  transit_gateway_id = module.tgw.id
  vpc_id             = module.vpc-inspect.vpc_id
  depends_on         = [module.tgw]
  tags               = local.tags
}

resource "aws_ec2_transit_gateway_route" "internet" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc-inspect.id
  transit_gateway_route_table_id = module.tgw.vpc_route_table.id
  depends_on                     = [module.tgw]
}


