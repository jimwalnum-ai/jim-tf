locals {
  env_name = "${var.name}-${var.env}"
  flow_log_bucket_name = "vpc-${var.name}-${var.env}-flow-logs"
  tag_name = lookup(aws_vpc.vpc.tags, "Name")
  azs      = [for i in range(var.private_subnets_count) : format("%s%s", var.region, i < 3 ? ["a", "b", "c"][i] : "")]
}

resource "aws_vpc" "vpc" {
  ipv4_ipam_pool_id   = var.ipv4_ipam_pool_id
  ipv4_netmask_length = var.ipv4_netmask_length
  enable_dns_hostnames = true
  tags = merge(var.tags, {"Name":"vpc-${var.name}-${var.env}","Spoke":"true","env":var.env})
}

resource "aws_flow_log" "vpc_flow_log" {
  log_destination      = var.flow_log_bucket
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.vpc.id
}

resource "aws_vpc_dhcp_options" "dhcp" {
  domain_name_servers = ["AmazonProvidedDNS"]
  tags = {
    Name = "${local.env_name}-DHCP-options"
  }
}

resource "aws_vpc_dhcp_options_association" "ntp_domain_association" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.dhcp.id
}

resource "aws_network_acl" "acl" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.env_name}-Network-ACL"
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
resource "aws_subnet" "tgw_subnets" {
  count             = var.private_subnets_count
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 3, count.index)
  availability_zone = local.azs[count.index]
  tags = "${merge(var.tags,{Name="${local.env_name}-tgw-subnet-${local.azs[count.index]}",scope="private",type="tgw"})}"
}

resource "aws_subnet" "protected_subnets" {
  count             = var.private_subnets_count
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 3, var.private_subnets_count  + count.index)
  availability_zone = local.azs[count.index]
  tags = "${merge(var.tags,{Name="${local.env_name}-protected-subnet-${local.azs[count.index]}",scope="private"})}"
}

resource "aws_subnet" "public_subnets" {
  count             = var.public_subnets_count
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 3, 2*var.private_subnets_count  + count.index)
  availability_zone = local.azs[count.index]
  tags = "${merge(var.tags,{Name="${local.env_name}-public-subnet-${local.azs[count.index]}",scope="public"})}"
}

resource "aws_internet_gateway" "internet_gateway" {
  count = var.create_igw || var.test ? 1 : 0
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name = "${local.env_name}-igw"
  }
}

resource "aws_route_table" "internet_gateway" {
  count = var.create_igw || var.test ? 1 : 0
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway[0].id
  }
}

resource "aws_route_table_association" "internet_gateway" {
  count = var.create_igw || var.test ? var.public_subnets_count : 0
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.internet_gateway[0].id
}

resource "aws_eip" "nat_gateway" {
  count = var.create_nat ? 1 : 0
}

resource "aws_nat_gateway" "nat_gateway" {
  count = var.create_nat ? var.private_subnets_count : 0
  allocation_id = aws_eip.nat_gateway[0].id
  subnet_id = aws_subnet.tgw_subnets[count.index].id
  tags = {
    "Name" = ""
  }
}

resource "aws_route_table" "nat_gateway" {
  count = var.create_nat ? 1 : 0
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
  }
}

#resource "aws_route_table_association" "nat_gateway" {
#  count = var.create_nat ? 1 : 0
#  subnet_id = aws_subnet.private_subnets[count.index].id
#  route_table_id = aws_route_table.nat_gateway[count.index].id
#}

resource "aws_network_acl_association" "tgw_sub_assoc" {
  count          = var.private_subnets_count
  subnet_id      = aws_subnet.tgw_subnets[count.index].id
  network_acl_id = aws_network_acl.acl.id
}

resource "aws_network_acl_association" "protected_sub_assoc" {
  count          = var.private_subnets_count
  subnet_id      = aws_subnet.protected_subnets[count.index].id
  network_acl_id = aws_network_acl.acl.id
}

resource "aws_network_acl_association" "public_sub_assoc" {
  count          = var.public_subnets_count
  subnet_id      = aws_subnet.public_subnets[count.index].id
  network_acl_id = aws_network_acl.acl.id
}

###############
# VPC Endpoints
###############

# Always want s3 endpoint, Gateway endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  tags = {
    Name = "${local.env_name}-s3-gateway"
  }
}

resource "aws_security_group" "endpoints" {
  name        = "endpoint-security-group"
  description = "VPC endpoint security group"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
}

resource "aws_vpc_endpoint" "endpoints" {
  for_each = toset(var.endpoint_list)
    vpc_id            = aws_vpc.vpc.id
    service_name      = "com.amazonaws.${var.region}.${each.value}"
    vpc_endpoint_type = "Interface"
    security_group_ids = [aws_security_group.endpoints.id]
    tags = {
      Name = "${local.env_name}-${each.value}-interface"
    }
}

resource "aws_vpc_endpoint_policy" "policy" {
  for_each = setsubtract(toset(var.endpoint_list),["eks"])
    vpc_endpoint_id = aws_vpc_endpoint.endpoints[each.value].id
    policy = templatefile("${path.module}/templates/endpoint_policy.json.tpl",{ user = var.endpoint_access_role})
}


