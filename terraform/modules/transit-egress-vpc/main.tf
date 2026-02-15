locals {
  env_name = "${var.name}-${var.env}"
  tag_name = lookup(aws_vpc.vpc.tags, "Name")
  azs      = [for i in range(var.private_subnets_count) : format("%s%s", var.region, i < 3 ? ["a", "b", "c"][i] : "")]
}

resource "aws_vpc" "vpc" {
 ipv4_ipam_pool_id   = var.ipv4_ipam_pool_id
 ipv4_netmask_length =	var.ipv4_netmask_length
  enable_dns_hostnames = true
  tags = merge(var.tags, {"Name":"vpc-${var.name}-${var.env}"})
}

resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = var.flow_log_bucket
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.vpc.id
}

resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.vpc.id
  route_table_id = aws_route_table.vpc.id
}

resource "aws_route_table" "vpc" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route" "routes" {
  count = length(var.vpc_attach_cidrs) 
  route_table_id  = aws_route_table.vpc.id
  destination_cidr_block = var.vpc_attach_cidrs[count.index]
  transit_gateway_id = var.transit_gateway
}

resource "aws_route" "igw-route" {
  route_table_id  = aws_route_table.vpc.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.internet_gateway.id
}

resource "aws_vpc_dhcp_options" "dhcp" {
  domain_name = "local"
  domain_name_servers = try(var.domain_name_servers,["AmazonProvidedDNS"])
  tags = {
    Name = "${local.env_name}-dhcp-options"
  }
}

resource "aws_vpc_dhcp_options_association" "ntp_domain_association" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.dhcp.id
}

resource "aws_network_acl" "acl" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.env_name}-network-acl"
  }
}

#Default ACL's
resource "aws_network_acl_rule" "allow_all_inbound" {
  network_acl_id = aws_network_acl.acl.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}
resource "aws_network_acl_rule" "allow_all_outbound" {
  network_acl_id = aws_network_acl.acl.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# Subnets
resource "aws_subnet" "private_subnets" {
  count             = var.private_subnets_count
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 2, count.index)
  availability_zone = local.azs[count.index]
  tags = "${merge(var.tags,{Name="${local.env_name}-private-subnet-${local.azs[count.index]}",scope="private"})}"
}

resource "aws_subnet" "public_subnets" {
  count             = var.public_subnets_count
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 2, count.index + var.private_subnets_count)
  availability_zone = local.azs[count.index]
  tags = "${merge(var.tags,{Name="${local.env_name}-public-subnet-${local.azs[count.index]}",scope="public"})}"
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name = "${local.env_name}-igw"
  }
}

resource "aws_route_table_association" "internet_gateway" {
  count = var.public_subnets_count 
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.vpc.id
}

resource "aws_eip" "nat_gateway" {
  count = var.public_subnets_count
}

# Attach NATS to public subnets
resource "aws_nat_gateway" "nat_gateway" {
  count = var.public_subnets_count
  allocation_id = aws_eip.nat_gateway[count.index].id
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    "Name" = ""
  }
}

resource "aws_route_table" "nat_gateway" {
  count = var.private_subnets_count
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
  }
}

resource "aws_route_table_association" "nat_gateway" {
  count = var.private_subnets_count
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.nat_gateway[count.index].id
}

resource "aws_network_acl_association" "private_sub_assoc" {
  count          = var.private_subnets_count
  subnet_id      = aws_subnet.private_subnets[count.index].id
  network_acl_id = aws_network_acl.acl.id
}

resource "aws_network_acl_association" "public_sub_assoc" {
  count          = var.public_subnets_count
  subnet_id      = aws_subnet.public_subnets[count.index].id
  network_acl_id = aws_network_acl.acl.id
}

