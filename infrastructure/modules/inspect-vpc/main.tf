locals {
  env_name             = "vpc-${var.name}-${var.env}-cs"
  flow_log_bucket_name = "vpc-${var.name}-${var.env}-flow-logs"
  tag_name             = lookup(aws_vpc.vpc.tags, "Name")
  default_azs          = sort(data.aws_availability_zones.available.names)
  azs_source           = length(var.availability_zones) > 0 ? var.availability_zones : local.default_azs
  available_azs        = slice(local.azs_source, 0, 2)
  internal_ingress_cidrs_map = merge(
    { "vpc" = { cidr = aws_vpc.vpc.cidr_block, rule_offset = 0 } },
    { "super" = { cidr = var.super_cidr_block, rule_offset = 1 } },
    { for idx, cidr in var.internal_ingress_cidrs : "internal-${idx}" => { cidr = cidr, rule_offset = idx + 2 } }
  )
  public_ingress_cidrs     = var.public_ingress_cidrs
  public_ingress_cidrs_map = { for idx, cidr in local.public_ingress_cidrs : cidr => idx }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  ipv4_ipam_pool_id    = var.ipv4_ipam_pool_id
  ipv4_netmask_length  = var.ipv4_netmask_length
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { "Name" : "${local.env_name}-vpc" })
}

resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = var.flow_log_bucket
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.vpc.id
}

resource "aws_subnet" "inspection_vpc_firewall_subnet" {
  count                   = 2
  availability_zone       = local.available_azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 4, count.index)
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${local.env_name}-firewall-subnet-${local.available_azs[count.index]}", scope = "private" })
}

resource "aws_subnet" "inspection_vpc_public_subnet" {
  count                   = 2
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.available_azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 4, 2 + count.index)
  depends_on              = [aws_internet_gateway.inspection_vpc_igw]
  tags                    = merge(var.tags, { Name = "${local.env_name}-public-subnet-${local.available_azs[count.index]}", scope = "public" })

}
resource "aws_subnet" "inspection_vpc_tgw_subnet" {
  count                   = 2
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.available_azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 4, var.tgw_subnet_cidr_offset + count.index)
  tags                    = merge(var.tags, { Name = "${local.env_name}-tgw-subnet-${local.available_azs[count.index]}", scope = "private" })
}

resource "aws_network_acl" "public_acl" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.env_name}-public-network-acl"
  }
}

resource "aws_network_acl" "private_acl" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.env_name}-private-network-acl"
  }
}

resource "aws_network_acl_rule" "public_inbound_internal" {
  for_each       = local.internal_ingress_cidrs_map
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 100 + each.value.rule_offset
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
}

resource "aws_network_acl_rule" "public_inbound_ssh" {
  for_each       = local.public_ingress_cidrs_map
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 200 + each.value
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.key
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "public_inbound_https" {
  for_each       = local.public_ingress_cidrs_map
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 300 + each.value
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.key
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_inbound_ephemeral" {
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 400
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "public_outbound_internal" {
  for_each       = local.internal_ingress_cidrs_map
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 100 + each.value.rule_offset
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
}

resource "aws_network_acl_rule" "public_outbound_http" {
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 200
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_outbound_https" {
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 210
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_outbound_ephemeral" {
  network_acl_id = aws_network_acl.public_acl.id
  rule_number    = 220
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_inbound_internal" {
  for_each       = local.internal_ingress_cidrs_map
  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = 100 + each.value.rule_offset
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
}

resource "aws_network_acl_rule" "private_outbound_internal" {
  for_each       = local.internal_ingress_cidrs_map
  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = 100 + each.value.rule_offset
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = each.value.cidr
}

resource "aws_network_acl_rule" "private_outbound_http" {
  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = 200
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "private_outbound_https" {
  network_acl_id = aws_network_acl.private_acl.id
  rule_number    = 210
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_association" "firewall_sub_assoc" {
  count          = 2
  subnet_id      = aws_subnet.inspection_vpc_firewall_subnet[count.index].id
  network_acl_id = aws_network_acl.private_acl.id
}

resource "aws_network_acl_association" "tgw_sub_assoc" {
  count          = 2
  subnet_id      = aws_subnet.inspection_vpc_tgw_subnet[count.index].id
  network_acl_id = aws_network_acl.private_acl.id
}

resource "aws_network_acl_association" "public_sub_assoc" {
  count          = 2
  subnet_id      = aws_subnet.inspection_vpc_public_subnet[count.index].id
  network_acl_id = aws_network_acl.public_acl.id
}

resource "aws_internet_gateway" "inspection_vpc_igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "inspection-vpc/internet-gateway"
  }
}
resource "aws_eip" "inspection_vpc_nat_gw_eip" {
  count = 2
}

resource "aws_nat_gateway" "inspection_vpc_nat_gw" {
  count         = 2
  depends_on    = [aws_internet_gateway.inspection_vpc_igw, aws_subnet.inspection_vpc_public_subnet]
  allocation_id = aws_eip.inspection_vpc_nat_gw_eip[count.index].id
  subnet_id     = aws_subnet.inspection_vpc_public_subnet[count.index].id
  tags = {
    Name = "inspection-vpc/${local.available_azs[count.index]}/nat-gateway"
  }
}



